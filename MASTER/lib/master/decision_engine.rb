# frozen_string_literal: true

module Master
  # DecisionEngine — priority score (impact * confidence / cost).
  # Used by ModelRouter for tier selection.
  module DecisionEngine
    EPSILON = 1e-6

    module_function

    def score(impact:, confidence:, cost:)
      safe_cost = [cost.to_f, EPSILON].max
      (impact.to_f * confidence.to_f) / safe_cost
    end
  end
end
