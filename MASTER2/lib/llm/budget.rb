# frozen_string_literal: true

module MASTER
  module LLM
    class << self
      def budget_thresholds
        @budget_thresholds ||= begin
          thresholds = MASTER::Paths.load_yaml("budget")&.dig(:budget, :thresholds)
          unless thresholds
            MASTER::Logging.warn("budget.yml missing 'thresholds' — using emergency fallback", subsystem: "llm.budget") if defined?(MASTER::Logging)
            return { premium: 8.0, strong: 5.0, fast: 1.0, cheap: 0.0 }
          end
          thresholds
        end
      end

      def spending_cap
        SPENDING_CAP
      end

      def total_spent
        return 0.0 unless defined?(DB)
        DB.total_cost
      end

      def budget_remaining
        [spending_cap - total_spent, 0.0].max
      end

      # Pick best available model
      def pick(tier_override = nil)
        select_model
      end

      # Alias for pick (used by Council)
      def select_available_model
        select_model
      end

      def tier
        return @forced_tier if @forced_tier
        r = budget_remaining
        thresholds = budget_thresholds
        if r > thresholds[:premium]
          :premium
        elsif r > thresholds[:strong]
          :strong
        elsif r > thresholds[:fast]
          :fast
        else
          :cheap
        end
      end

      def record_cost(model:, tokens_in:, tokens_out:)
        # Simplified cost recording - prefer using response.cost from RubyLLM
        # Fallback to manual calculation if needed
        base_model = model.split(":").first  # Remove suffixes
        rates = model_rates.fetch(base_model, { in: 1.0, out: 1.0 })
        cost = (tokens_in * rates[:in] + tokens_out * rates[:out]) / 1_000_000.0
        DB.log_cost(model: base_model, tokens_in: tokens_in, tokens_out: tokens_out, cost: cost) if defined?(DB)
        cost
      end
    end
  end
end
