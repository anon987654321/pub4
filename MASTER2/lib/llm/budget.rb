# frozen_string_literal: true

# Budgeting removed — OpenRouter handles credit limits natively.
# Stub methods kept for interface compatibility.

module MASTER
  module LLM
    class << self
      def budget_thresholds
        { premium: 0, strong: 0, fast: 0, cheap: 0 }.freeze
      end

      def spending_cap
        Float::INFINITY
      end

      def total_spent
        0.0
      end

      def budget_remaining
        Float::INFINITY
      end

      def pick(_tier = nil)
        select_model
      end

      def tier
        return @forced_tier if @forced_tier
        :strong
      end

      def record_cost(model:, tokens_in:, tokens_out:)
        0.0
      end
    end
  end
end
