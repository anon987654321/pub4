# frozen_string_literal: true

begin
  require "ruby_llm"
rescue LoadError
  # ruby_llm not available
end

module MASTER
  module LLM
    RATES = {
      "deepseek/deepseek-r1" => { in: 0.55 / 1_000_000, out: 2.19 / 1_000_000, tier: :strong },
      "anthropic/claude-sonnet-4" => { in: 3.0 / 1_000_000, out: 15.0 / 1_000_000, tier: :strong },
      "deepseek/deepseek-v3" => { in: 0.27 / 1_000_000, out: 1.10 / 1_000_000, tier: :fast },
      "openai/gpt-4.1-mini" => { in: 0.40 / 1_000_000, out: 1.60 / 1_000_000, tier: :fast },
      "openai/gpt-4.1-nano" => { in: 0.10 / 1_000_000, out: 0.40 / 1_000_000, tier: :cheap }
    }.freeze

    BUDGET_LIMIT = 10.0 # dollars
    CIRCUIT_THRESHOLD = 3 # consecutive failures
    CIRCUIT_COOLDOWN = 300 # seconds

    class << self
      def configure
        return unless defined?(RubyLLM)
        
        RubyLLM.configure do |config|
          config.openrouter_api_key = ENV["OPENROUTER_API_KEY"]
        end
      end

      def chat(model:)
        return nil unless defined?(RubyLLM)
        return nil unless ENV["OPENROUTER_API_KEY"]
        
        RubyLLM.chat(model: model)
      end

      # Select cheapest model in most powerful affordable tier
      def pick
        select_model(0)
      end

      def select_model(text_length)
        current_tier = affordable_tier
        return nil unless current_tier

        # Get all models in current tier that are healthy
        candidates = RATES.select { |_model, data| data[:tier] == current_tier }
                          .keys
                          .select { |model| healthy?(model) }

        return nil if candidates.empty?

        # Return cheapest model (lowest output cost, since that's usually the bottleneck)
        candidates.min_by { |model| RATES[model][:out] }
      end

      # Get current affordable tier
      def tier
        affordable_tier
      end

      def affordable_tier
        budget_left = remaining

        # Try tiers from most to least powerful
        [:strong, :fast, :cheap].each do |tier_level|
          # Get cheapest model in this tier
          cheapest = RATES.select { |_k, v| v[:tier] == tier_level }
                          .min_by { |_k, v| v[:out] }

          next unless cheapest

          # Estimate: assume 1000 tokens in, 1000 tokens out
          estimated_cost = (cheapest[1][:in] * 1000) + (cheapest[1][:out] * 1000)

          # If we can afford at least one call at this tier, return it
          return tier_level if budget_left >= estimated_cost
        end

        nil # No affordable tier
      end

      def remaining
        BUDGET_LIMIT - DB.total_cost
      end

      # Check if model circuit is healthy (not tripped)
      def healthy?(model)
        circuit_available?(model)
      end

      def circuit_available?(model)
        circuit_data = DB.circuit(model)
        return true unless circuit_data # No circuit record = healthy

        state = circuit_data["state"]
        failures = circuit_data["failures"].to_i
        last_failure = circuit_data["last_failure"]

        # If circuit is closed (healthy) and failures < threshold, it's available
        return true if state == "closed" && failures < CIRCUIT_THRESHOLD

        # If circuit is tripped, check cooldown
        if state == "open" && last_failure
          last_failure_time = Time.parse(last_failure)
          cooldown_elapsed = Time.now - last_failure_time > CIRCUIT_COOLDOWN
          
          # Reset circuit if cooldown elapsed
          if cooldown_elapsed
            DB.reset!(model)
            return true
          end
        end

        false
      end

      # Record cost to database
      def record_cost(model:, tokens_in:, tokens_out:)
        rates = RATES[model]
        return unless rates

        cost = (rates[:in] * tokens_in) + (rates[:out] * tokens_out)
        DB.log_cost(model: model, tokens_in: tokens_in, tokens_out: tokens_out, cost: cost)
      end

      # Record LLM failure for circuit breaker
      def record_failure(model)
        DB.trip!(model)
      end

      # Record LLM success for circuit breaker
      def record_success(model)
        circuit_data = DB.circuit(model)
        
        # Reset failures on success
        if circuit_data && circuit_data["failures"].to_i > 0
          DB.reset!(model)
        end
      end

      # Alias for backward compatibility
      def log_cost(model:, tokens_in:, tokens_out:)
        record_cost(model: model, tokens_in: tokens_in, tokens_out: tokens_out)
      end
    end
  end
end
