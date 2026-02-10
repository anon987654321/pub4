# frozen_string_literal: true

module MASTER
  # LearningQuality - Assess and filter learning data quality
  module LearningQuality
    extend self

    MIN_CONFIDENCE = 0.6

    def assess(learning)
      confidence = calculate_confidence(learning)
      {
        confidence: confidence,
        quality: confidence >= MIN_CONFIDENCE ? :acceptable : :low,
        usable: confidence >= MIN_CONFIDENCE
      }
    end

    private

    def calculate_confidence(learning)
      return 0.0 unless learning.is_a?(Hash)
      
      score = 0.0
      score += 0.3 if learning[:category]
      score += 0.3 if learning[:success]
      score += 0.2 if learning[:timestamp]
      score += 0.2 if learning[:fix_hash]
      score
    end
  end
end
