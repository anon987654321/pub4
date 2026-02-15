# frozen_string_literal: true

module MASTER
  # LearningQuality - Assess and filter learning data quality
  module LearningQuality
    extend self

    MIN_CONFIDENCE = 0.6
    MINIMUM_APPLICATIONS = 3

    # Confidence scoring weights
    WEIGHT_CATEGORY = 0.3
    WEIGHT_SUCCESS = 0.3
    WEIGHT_TIMESTAMP = 0.2
    WEIGHT_FIX_HASH = 0.2

    TIERS = {
      promote: { threshold: 0.85, action: "Promote to core patterns" },
      keep: { threshold: 0.60, action: "Keep in active set" },
      demote: { threshold: 0.30, action: "Demote to experimental" },
      retire: { threshold: 0.0, action: "Retire pattern" }
    }.freeze

    def assess(learning)
      confidence = calculate_confidence(learning)
      {
        confidence: confidence,
        quality: confidence >= MIN_CONFIDENCE ? :acceptable : :low,
        usable: confidence >= MIN_CONFIDENCE
      }
    end

    def evaluate(pattern)
      applications = pattern[:applications] || pattern[:applications] || 0
      return :unrated if applications < MINIMUM_APPLICATIONS

      success_rate = calculate_success_rate(pattern)

      case success_rate
      when 0.85..Float::INFINITY then :promote
      when 0.60...0.85 then :keep
      when 0.30...0.60 then :demote
      else :retire
      end
    end

    def tier(pattern)
      evaluate(pattern)
    end

    def calculate_success_rate(pattern)
      successes = (pattern[:successes] || pattern[:successes] || 0).to_f
      failures = (pattern[:failures] || pattern[:failures] || 0).to_f
      total = successes + failures

      return 0.0 if total.zero?
      successes / total
    end

    private

    def calculate_confidence(learning)
      return 0.0 unless learning.is_a?(Hash)

      score = 0.0
      score += WEIGHT_CATEGORY if learning[:category]
      score += WEIGHT_SUCCESS if learning[:success]
      score += WEIGHT_TIMESTAMP if learning[:timestamp]
      score += WEIGHT_FIX_HASH if learning[:fix_hash]
      score
    end
  end
end
