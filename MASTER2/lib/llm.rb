# frozen_string_literal: true

require "ruby_llm"
require "time"

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
    STRONG_THRESHOLD = 5.0
    FAST_THRESHOLD = 1.0

    def self.configure
      RubyLLM.configure do |config|
        config.openai_api_key = ENV["OPENAI_API_KEY"]
        config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
        config.deepseek_api_key = ENV["DEEPSEEK_API_KEY"]
        config.openrouter_api_key = ENV["OPENROUTER_API_KEY"]
      end
    end

    def self.pick
      tier_level = tier
      return nil unless tier_level

      candidates = RATES.select { |_k, v| v[:tier] == tier_level }.keys
      candidates.find { |model| healthy?(model) }
    end

    def self.healthy?(model)
      circuit = DB.circuit(model)
      return true unless circuit

      failures = circuit["failures"].to_i
      return true if failures < CIRCUIT_THRESHOLD

      begin
        last_failure = Time.parse(circuit["last_failure"])
      rescue ArgumentError
        last_failure = Time.now
      end
      Time.now - last_failure > CIRCUIT_COOLDOWN
    end

    def self.record_failure(model)
      DB.trip!(model)
    end

    def self.record_success(model)
      DB.reset!(model)
    end

    def self.log_cost(model:, tokens_in:, tokens_out:)
      rate = RATES[model]
      return unless rate

      cost = (tokens_in * rate[:in]) + (tokens_out * rate[:out])
      DB.log_cost(model: model, tokens_in: tokens_in, tokens_out: tokens_out, cost: cost)
    end

    def self.remaining
      BUDGET_LIMIT - DB.total_cost
    end

    def self.tier
      remaining_budget = remaining
      return nil if remaining_budget <= 0

      # Return the most powerful tier we can afford
      if remaining_budget > STRONG_THRESHOLD
        :strong
      elsif remaining_budget > FAST_THRESHOLD
        :fast
      else
        :cheap
      end
    end

    def self.chat(model:)
      RubyLLM.chat(model: model)
    end
  end
end
