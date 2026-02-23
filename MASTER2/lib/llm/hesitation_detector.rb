# frozen_string_literal: true

module MASTER
  module LLM
    # HesitationDetector — predict whether council debate will help
    # Based on iMAD (AAAI 2026, arXiv:2511.11306): saves ~92% council compute
    # by only escalating to multi-agent debate when primary agent shows uncertainty.
    module HesitationDetector
      module_function

      # Linguistic uncertainty markers (calibrated from iMAD paper)
      UNCERTAINTY_PATTERNS = [
        /\b(?:I'm|I am)\s+not\s+(?:sure|certain|confident)/i,
        /\b(?:might|may|could|possibly|perhaps|probably)\b/i,
        /\bnot\s+(?:entirely|completely|fully)\s+(?:sure|clear|certain)/i,
        /\b(?:unclear|ambiguous|uncertain|unsure)\b/i,
        /\b(?:it depends|hard to say|difficult to determine)\b/i,
        /\b(?:on the one hand|on the other hand|alternatively)\b/i,
        /\b(?:I think|I believe|in my opinion|it seems)\b/i,
        /\?\s*$/, # ends with a question
      ].freeze

      # Confidence threshold: below this, escalate to council
      CONFIDENCE_THRESHOLD = 0.7
      # Confidence reduction per uncertainty marker
      UNCERTAINTY_PENALTY = 0.12
      # Floor confidence score — never drop below this
      MIN_CONFIDENCE_SCORE = 0.1
      # Max chars of context shown in log
      CONTEXT_PREVIEW_LENGTH = 60

      # Estimate confidence score of LLM response (0.0–1.0).
      # Lower score = more uncertainty = more likely to need council.
      # @param response [String] LLM primary response
      # @return [Float] confidence score 0.0–1.0
      def confidence_score(response)
        return 0.0 unless response.is_a?(String) && !response.empty?

        matches = UNCERTAINTY_PATTERNS.count { |p| p.match?(response) }
        # Each uncertainty marker reduces confidence by UNCERTAINTY_PENALTY (capped)
        [1.0 - (matches * UNCERTAINTY_PENALTY), MIN_CONFIDENCE_SCORE].max
      end

      # Should the council be invoked for this response?
      # @param response [String] primary LLM response
      # @return [Boolean]
      def hesitant?(response)
        confidence_score(response) < CONFIDENCE_THRESHOLD
      end

      # Log the hesitation decision for AutoTool-style learning.
      def evaluate(response, context: nil)
        score = confidence_score(response)
        escalate = score < CONFIDENCE_THRESHOLD

        Logging.dmesg_log("hesit0",
                          message: "score=#{score.round(2)} escalate=#{escalate} context=#{context&.to_s&.slice(0, CONTEXT_PREVIEW_LENGTH)}")

        { score: score, escalate: escalate }
      end
    end
  end
end
