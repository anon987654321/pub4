# frozen_string_literal: true

require "ruby_llm"

module MASTER
  module LLM
    TIERS = {
      strong: %w[deepseek/deepseek-r1 anthropic/claude-sonnet-4],
      fast:   %w[deepseek/deepseek-v3 openai/gpt-4.1-mini],
      cheap:  %w[openai/gpt-4.1-nano],
    }.freeze

    TIER_ORDER = %i[strong fast cheap].freeze

    RATES = {
      "deepseek/deepseek-r1"     => { in: 0.55, out: 2.19, tier: :strong },
      "anthropic/claude-sonnet-4" => { in: 3.00, out: 15.00, tier: :strong },
      "deepseek/deepseek-v3"     => { in: 0.27, out: 1.10, tier: :fast },
      "openai/gpt-4.1-mini"      => { in: 0.40, out: 1.60, tier: :fast },
      "openai/gpt-4.1-nano"      => { in: 0.10, out: 0.40, tier: :cheap },
    }.freeze

    CIRCUIT_THRESHOLD = 3
    CIRCUIT_COOLDOWN  = 300
    BUDGET_LIMIT      = 10.0

    class << self
      def configure
        RubyLLM.configure do |c|
          c.openrouter_api_key = ENV["OPENROUTER_API_KEY"]
        end
      end

      def chat(model:)
        RubyLLM.chat(model: model)
      end

      # Select model based on text length, circuit state, and budget
      def select_model(text_length = 0)
        desired = text_length > 1000 ? :strong : text_length > 200 ? :fast : :cheap
        start = [TIER_ORDER.index(desired), TIER_ORDER.index(tier)].max

        TIER_ORDER[start..].each do |t|
          TIERS[t].each { |m| return { model: m, tier: t } if healthy?(m) }
        end
        nil
      end

      # Alias for compatibility
      def pick
        result = select_model(500)
        result ? result[:model] : nil
      end

      # Circuit breaker
      def healthy?(model)
        row = DB.circuit(model)
        return true unless row
        return true if row["state"] == "closed"
        if Time.now.utc - Time.parse(row["last_failure"]) > CIRCUIT_COOLDOWN
          reset!(model)
          true
        else
          false
        end
      end

      def trip!(model)
        DB.trip!(model)
      end

      def reset!(model)
        DB.reset!(model)
      end

      # Budget
      def spent
        DB.total_cost
      end

      def remaining
        BUDGET_LIMIT - spent
      end

      def tier
        r = remaining
        r > 5.0 ? :strong : r > 1.0 ? :fast : :cheap
      end

      def record_cost(model:, tokens_in:, tokens_out:)
        rates = RATES.fetch(model, { in: 1.0, out: 1.0 })
        cost = (tokens_in * rates[:in] + tokens_out * rates[:out]) / 1_000_000.0
        DB.log_cost(model: model, tokens_in: tokens_in, tokens_out: tokens_out, cost: cost)
        cost
      end
    end
  end
end
