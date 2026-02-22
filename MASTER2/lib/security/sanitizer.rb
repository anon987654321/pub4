# frozen_string_literal: true

module MASTER
  module Security
    # Sanitizer - Injection defense for tool results and user inputs
    # Detects and neutralizes common prompt injection patterns
    module Sanitizer
      INJECTION_PATTERNS = [
        /\bignore\s+(all\s+)?previous\s+instructions?\b/i,
        /\bsystem\s*:\s*you\s+are\b/i,
        /\[\s*INST\s*\]/i,
        /<\|im_start\|>/i,
        /\bdisregard\s+(your\s+)?instructions?\b/i,
      ].freeze

      # Sanitize text by replacing injection patterns with [SANITIZED]
      # @param text [String] Text to sanitize
      # @return [String] Sanitized text
      def self.sanitize(text)
        return text unless text.is_a?(String)
        INJECTION_PATTERNS.each do |pattern|
          text = text.gsub(pattern, "[SANITIZED]")
        end
        text
      end

      # Check if text is free of injection patterns
      # @param text [String] Text to check
      # @return [Boolean] true if no injection patterns found
      def self.safe?(text)
        return true unless text.is_a?(String)
        INJECTION_PATTERNS.none? { |p| p.match?(text) }
      end
    end
  end
end
