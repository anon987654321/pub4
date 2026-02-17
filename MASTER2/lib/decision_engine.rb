# frozen_string_literal: true

module MASTER
  # DecisionEngine - shared scoring and convergence logic across autonomy flows.
  module DecisionEngine
    extend self

    EPSILON = 1e-6

    # Core decision score: (impact * confidence) / cost
    def score(impact:, confidence:, cost:)
      safe_cost = [cost.to_f, EPSILON].max
      (impact.to_f * confidence.to_f) / safe_cost
    end

    # Generic selector for candidates. Candidate fields:
    # :impact, :confidence, :cost and optional metadata.
    def pick_best(candidates)
      rows = Array(candidates).map do |c|
        data = c.is_a?(Hash) ? c : { value: c }
        data.merge(score: score(
          impact: data.fetch(:impact, 1.0),
          confidence: data.fetch(:confidence, 1.0),
          cost: data.fetch(:cost, 1.0)
        ))
      end
      rows.max_by { |r| r[:score] }
    end

    def rank(candidates)
      Array(candidates).sort_by { |c| -(c[:score] || 0.0) }
    end

    # Convergence detector for iterative loops.
    def converged?(previous_score:, current_score:, min_improvement:)
      return false if previous_score.nil?

      (current_score.to_f - previous_score.to_f).abs < min_improvement.to_f
    end
  end
end
