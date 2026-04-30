# frozen_string_literal: true

module Master
  # DecisionEngine — universal priority scorer.
  # Formula: (impact * confidence) / cost
  # Used by: ModelRouter (model selection), Heartbeat (job ordering),
  #          AutoLoop (file ordering), Swarm (worker result weighting).
  module DecisionEngine
    EPSILON = 1e-6

    module_function

    def score(impact:, confidence:, cost:)
      safe_cost = [cost.to_f, EPSILON].max
      (impact.to_f * confidence.to_f) / safe_cost
    end

    def pick_best(candidates)
      ranked(candidates).first
    end

    def ranked(candidates)
      Array(candidates).map do |c|
        c = { value: c } unless c.is_a?(Hash)
        c.merge(de_score: score(
          impact:     c.fetch(:impact,     c.fetch("impact",     1.0)),
          confidence: c.fetch(:confidence, c.fetch("confidence", 1.0)),
          cost:       c.fetch(:cost,       c.fetch("cost",       1.0))
        ))
      end.sort_by { |c| -c[:de_score] }
    end

    def converged?(previous:, current:, min_delta: 0.001)
      return false if previous.nil?
      (current.to_f - previous.to_f).abs < min_delta.to_f
    end
  end
end
