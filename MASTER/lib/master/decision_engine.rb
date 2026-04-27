# frozen_string_literal: true

module Master
  # DecisionEngine — shared scoring and convergence logic.
  # Ported from MASTER2. Scores candidates by (impact * confidence) / cost.
  # Used by Heartbeat for job ranking and ModelRouter for model selection.
  module DecisionEngine
    EPSILON = 1e-6.freeze

    module_function

    def score(impact:, confidence:, cost:)
      safe_cost = [cost.to_f, EPSILON].max
      (impact.to_f * confidence.to_f) / safe_cost
    end

    def pick_best(candidates)
      rows = Array(candidates).map do |c|
        data = c.is_a?(Hash) ? c : { value: c }
        data.merge(score: score(
          impact:     data.fetch(:impact, 1.0),
          confidence: data.fetch(:confidence, 1.0),
          cost:       data.fetch(:cost, 1.0)
        ))
      end
      rows.max_by { |r| r[:score] }
    end

    def rank(candidates)
      Array(candidates).sort_by { |c| -(c[:score] || 0.0) }
    end

    def converged?(previous_score:, current_score:, min_improvement: 0.001)
      return false if previous_score.nil?

      (current_score.to_f - previous_score.to_f).abs < min_improvement.to_f
    end
  end
end
