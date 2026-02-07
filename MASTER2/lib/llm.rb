# frozen_string_literal: true

require "ruby_llm"

module MASTER
  # LLM - Model selection, circuit breaker, cost tracking
  module LLM
    MODEL_TIERS = {
      strong: %w[deepseek/deepseek-r1 anthropic/claude-sonnet-4],
      fast: %w[deepseek/deepseek-v3 openai/gpt-4.1-mini],
      cheap: %w[openai/gpt-4.1-nano],
    }.freeze

    TIER_ORDER = %i[strong fast cheap].freeze

    MODEL_RATES = {
      "deepseek/deepseek-r1" => { in: 0.55, out: 2.19, tier: :strong },
      "anthropic/claude-sonnet-4" => { in: 3.00, out: 15.00, tier: :strong },
      "deepseek/deepseek-v3" => { in: 0.27, out: 1.10, tier: :fast },
      "openai/gpt-4.1-mini" => { in: 0.40, out: 1.60, tier: :fast },
      "openai/gpt-4.1-nano" => { in: 0.10, out: 0.40, tier: :cheap },
    }.freeze

    FAILURES_BEFORE_TRIP = 3
    CIRCUIT_RESET_SECONDS = 300
    SPENDING_CAP = 10.0

    class << self
      def configure
        RubyLLM.configure do |c|
          c.openrouter_api_key = ENV.fetch("OPENROUTER_API_KEY", nil)
        end
      end

      def chat(model:)
        RubyLLM.chat(model: model)
      end

      def select_model(text_length = 0)
        desired = if text_length > 1000
                    :strong
                  elsif text_length > 200
                    :fast
                  else
                    :cheap
                  end
        start = [TIER_ORDER.index(desired), TIER_ORDER.index(tier)].max

        TIER_ORDER[start..].each do |t|
          MODEL_TIERS[t].each { |m| return { model: m, tier: t } if circuit_closed?(m) }
        end
        nil
      end

      def select_available_model
        result = select_model(500)
        result&.fetch(:model)
      end

      def circuit_closed?(model)
        row = DB.circuit(model)
        return true unless row

        state = row[:state]
        return true if state == "closed"

        last_failure = row[:last_failure]
        if Time.now.utc - Time.parse(last_failure) > CIRCUIT_RESET_SECONDS
          close_circuit!(model)
          true
        else
          false
        end
      end

      def open_circuit!(model)
        DB.trip!(model)
      end

      def close_circuit!(model)
        DB.reset!(model)
      end

      def total_spent
        DB.total_cost
      end

      def budget_remaining
        SPENDING_CAP - total_spent
      end

      def tier
        r = budget_remaining
        if r > 5.0
          :strong
        elsif r > 1.0
          :fast
        else
          :cheap
        end
      end

      def record_cost(model:, tokens_in:, tokens_out:)
        rates = MODEL_RATES.fetch(model, { in: 1.0, out: 1.0 })
        cost = (tokens_in * rates[:in] + tokens_out * rates[:out]) / 1_000_000.0
        DB.log_cost(model: model, tokens_in: tokens_in, tokens_out: tokens_out, cost: cost)
        cost
      end
    end
  end
end
