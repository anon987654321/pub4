# frozen_string_literal: true

require "ruby_llm"

module MASTER
  module LLM
    RATES = {
      "deepseek-r1" => { in: 0.55 / 1_000_000, out: 2.19 / 1_000_000, tier: :strong },
      "claude-sonnet-4" => { in: 3.0 / 1_000_000, out: 15.0 / 1_000_000, tier: :strong },
      "deepseek-v3" => { in: 0.27 / 1_000_000, out: 1.10 / 1_000_000, tier: :fast },
      "gpt-4.1-mini" => { in: 0.40 / 1_000_000, out: 1.60 / 1_000_000, tier: :fast },
      "gpt-4.1-nano" => { in: 0.10 / 1_000_000, out: 0.40 / 1_000_000, tier: :cheap }
    }.freeze

    CIRCUIT_THRESHOLD = 3
    CIRCUIT_COOLDOWN = 300 # seconds
    BUDGET_LIMIT = 10.0 # dollars

    class << self
      def configure
        RubyLLM.configure do |config|
          config.openai_api_key = ENV["OPENAI_API_KEY"]
          config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
          config.deepseek_api_key = ENV["DEEPSEEK_API_KEY"]
          config.openrouter_api_key = ENV["OPENROUTER_API_KEY"]
        end
      end

      def select_model(input_size = 0)
        tier = affordable_tier
        return nil unless tier

        candidates = RATES.select { |_k, v| v[:tier] == tier }.keys
        candidates.find { |model| circuit_available?(model) }
      end

      def circuit_available?(model)
        circuit = DB.get_circuit(model)
        return true unless circuit

        failures = circuit["failures"].to_i
        return true if failures < CIRCUIT_THRESHOLD

        last_failure = Time.parse(circuit["last_failure"]) rescue Time.now
        Time.now - last_failure > CIRCUIT_COOLDOWN
      end

      def record_failure(model)
        DB.record_circuit_failure(model)
      end

      def record_success(model)
        DB.record_circuit_success(model)
      end

      def record_cost(model:, tokens_in:, tokens_out:)
        rate = RATES[model]
        return unless rate

        cost = (tokens_in * rate[:in]) + (tokens_out * rate[:out])
        DB.record_cost(model: model, tokens_in: tokens_in, tokens_out: tokens_out, cost: cost)
      end

      def remaining
        BUDGET_LIMIT - DB.get_total_cost
      end

      def affordable_tier
        remaining_budget = remaining
        return nil if remaining_budget <= 0

        # Return the most powerful tier we can afford
        if remaining_budget > 5.0
          :strong
        elsif remaining_budget > 1.0
          :fast
        else
          :cheap
        end
      end

      def chat(model:)
        RubyLLM.chat(model: model)
      end
    end
  end
end
