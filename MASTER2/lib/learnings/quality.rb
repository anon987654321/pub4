# frozen_string_literal: true

module Learnings
  class Quality
    DEFAULT_MIN_SCORE = 0.8
    DEFAULT_WEIGHTS = {
      accuracy: 1.0,
      completeness: 1.0,
      clarity: 1.0
    }.freeze

    def initialize(options = {})
      @min_score = options.fetch(:min_score, DEFAULT_MIN_SCORE).to_f
      @strict = options.fetch(:strict, false)
      @weights = normalize_weights(options.fetch(:weights, DEFAULT_WEIGHTS))
    end

    def score(metrics)
      return 0.0 if metrics.nil?

      total_weight = @weights.values.sum
      return 0.0 if total_weight.zero?

      weighted_sum = @weights.sum do |key, weight|
        metrics.fetch(key, 0).to_f * weight
      end

      weighted_sum / total_weight
    end

    def pass?(metrics)
      score(metrics) >= @min_score
    end

    def evaluate(metrics)
      s = score(metrics)
      { score: s, pass: s >= @min_score, strict: @strict }
    end

    private

    def normalize_weights(weights)
      weights.to_h.transform_values(&:to_f).freeze
    end
  end
end