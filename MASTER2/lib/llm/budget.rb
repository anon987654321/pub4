# frozen_string_literal: true

# Budgeting removed — OpenRouter handles credit limits natively.
# Stub methods kept for backward compatibility.

module MASTER
  module LLM
    class << self
      def budget_thresholds
        @budget_thresholds ||= begin
          thresholds = MASTER::Paths.load_yaml("budget")&.dig(:budget, :thresholds)
          unless thresholds
            MASTER::Logging.warn("budget.yml missing 'thresholds' — using emergency fallback", subsystem: "llm.budget") if defined?(MASTER::Logging)

          end
          thresholds || { premium: 8.0, strong: 5.0, fast: 1.0, cheap: 0.0 }
        end
      end

      def spending_cap
        Float::INFINITY
      end

      def total_spent
        return 0.0 unless defined?(DB)
        DB.total_cost rescue 0.0
      end

      def budget_remaining
        Float::INFINITY
      end


      def tier
        return @forced_tier if @forced_tier
        :strong
      end

      def record_cost(model:, tokens_in:, tokens_out:)
        # Simplified cost recording - prefer using response.cost from RubyLLM
        # Fallback to manual calculation if needed
        base_model = model.split(":").first  # Strip version suffixes (e.g., "model:free")
        rates = model_rates.fetch(base_model, { in: 1.0, out: 1.0 })
        cost = (tokens_in * rates[:in] + tokens_out * rates[:out]) / 1_000_000.0
        DB.log_cost(model: base_model, tokens_in: tokens_in, tokens_out: tokens_out, cost: cost) if defined?(DB)
        cost
      end
    end
  end
end
