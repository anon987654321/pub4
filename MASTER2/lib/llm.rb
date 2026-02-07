# frozen_string_literal: true

require "ruby_llm"

module MASTER
  module LLM
    extend self

    # Model rates loaded from database at runtime
    RATES = {}
    CIRCUIT_THRESHOLD = 3
    BUDGET_LIMIT = 10.0

    # Configure LLM module by loading rates from database
    def configure
      models = DB.connection.execute("SELECT id, tier, input_cost, output_cost FROM models")
      models.each do |model|
        RATES[model["id"]] = {
          in: model["input_cost"],
          out: model["output_cost"],
          tier: model["tier"].to_sym
        }
      end
    end

    # Check if a model's circuit is healthy (not tripped)
    def healthy?(model)
      circuit = DB.circuit(model)
      return true unless circuit # No failures recorded
      circuit["failures"].to_i < CIRCUIT_THRESHOLD
    end

    # Record a failure for a model's circuit breaker
    def record_failure(model)
      DB.trip!(model)
    end

    # Record a success for a model's circuit breaker
    def record_success(model)
      # Success doesn't reset circuit, only explicit reset does
      # But we could implement gradual recovery here if needed
    end

    # Log cost to database and calculate actual cost
    def log_cost(model:, tokens_in:, tokens_out:)
      rate = RATES[model]
      return unless rate

      # Cost per 1M tokens, convert to actual cost
      cost = (tokens_in * rate[:in] / 1_000_000.0) + (tokens_out * rate[:out] / 1_000_000.0)
      DB.log_cost(model: model, tokens_in: tokens_in, tokens_out: tokens_out, cost: cost)
    end

    # Get remaining budget
    def remaining
      BUDGET_LIMIT - DB.total_cost
    end

    # Determine current tier based on remaining budget
    def tier
      remaining_budget = remaining
      
      # Get thresholds from config
      strong_threshold = DB.config("budget_threshold_strong")&.to_f || 5.0
      fast_threshold = DB.config("budget_threshold_fast")&.to_f || 1.0
      
      if remaining_budget >= strong_threshold
        :strong
      elsif remaining_budget >= fast_threshold
        :fast
      elsif remaining_budget > 0
        :cheap
      else
        nil # Budget exhausted
      end
    end

    # Pick a model from the current tier with healthy circuit
    def pick
      current_tier = tier
      return nil unless current_tier

      # Get models in current tier
      candidates = RATES.select { |_k, v| v[:tier] == current_tier }.keys
      
      # Filter to healthy models only
      healthy_models = candidates.select { |m| healthy?(m) }
      
      # Return first healthy model, or nil if none available
      healthy_models.first
    end

    # Create a chat instance with ruby_llm gem
    def chat(model:)
      RubyLLM.chat(
        provider: :openrouter,
        model: model,
        api_key: ENV["OPENROUTER_API_KEY"]
      )
    end

    # Select model based on text length (for backward compatibility)
    def select_model(text_length)
      pick
    end

    # Check if circuit is available (for backward compatibility)
    def circuit_available?(model)
      healthy?(model)
    end

    # Record cost (for backward compatibility)
    def record_cost(model:, tokens_in:, tokens_out:)
      log_cost(model: model, tokens_in: tokens_in, tokens_out: tokens_out)
    end
  end
end
