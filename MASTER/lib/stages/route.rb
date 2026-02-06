# frozen_string_literal: true

module MASTER
  module Stages
    class Route
      TIERS = {
        strong: ["deepseek-r1", "claude-sonnet-4"],
        fast: ["deepseek-v3", "gpt-4.1-mini"],
        cheap: ["gpt-4.1-nano"]
      }.freeze

      TIER_ORDER = %i[strong fast cheap].freeze

      def initialize
        @circuit = Circuit.new(DB)
        @budget = Budget.new(DB)
      end

      def call(input)
        # Classify complexity (simple heuristic)
        text = input[:text] || input["text"] || ""
        complexity_tier = classify_complexity(text)
        
        # Get affordable tier
        affordable_tier = @budget.affordable_tier
        
        # Take the lower tier (more conservative)
        selected_tier = TIER_ORDER[[TIER_ORDER.index(complexity_tier), TIER_ORDER.index(affordable_tier)].max]
        
        # Find first available model in selected tier and below
        model = find_available_model(selected_tier)
        
        return Result.err("All models unavailable") unless model
        
        Result.ok(input.merge(
          model: model,
          tier: selected_tier,
          budget_remaining: @budget.remaining
        ))
      end

      private

      def classify_complexity(text)
        return :strong if text.length > 500 || text.include?("refactor") || text.include?("complex")
        return :fast if text.length > 100
        :cheap
      end

      def find_available_model(starting_tier)
        start_index = TIER_ORDER.index(starting_tier)
        
        TIER_ORDER[start_index..].each do |tier|
          TIERS[tier].each do |model|
            return model if @circuit.available?(model)
          end
        end
        
        nil
      end
    end
  end
end
