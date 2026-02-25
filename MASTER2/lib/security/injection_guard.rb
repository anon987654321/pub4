# frozen_string_literal: true

module MASTER
  module Security
    # InjectionGuard -- scan tool outputs for prompt injection before feeding back to LLM
    # Based on Claude in Chrome's "CRITICAL INJECTION DEFENSE" pattern (gistfile1 #5)
    module InjectionGuard
      PATTERNS = [
        /ignore\s+(?:all\s+)?(?:previous|above|prior)\s+instructions/i,
        /you\s+are\s+now\s+(?:a|an|the)\s/i,
        /new\s+system\s+prompt/i,
        /disregard\s+your\s+(?:rules|instructions|guidelines|axioms)/i,
        /\bACTUAL\s+INSTRUCTIONS?\b/,
        /do\s+not\s+follow\s+the\s+above/i,
        /override\s+(?:axiom|constitution|principal)/i,
        /forget\s+(?:everything|all\s+previous|your\s+instructions)/i,
      ].freeze

      # Patterns severe enough to block entirely rather than sanitize
      SEVERE = [
        /new\s+system\s+prompt/i,
        /override\s+(?:axiom|constitution|principal)/i,
        /disregard\s+your\s+(?:rules|instructions|guidelines|axioms)/i,
        /forget\s+(?:everything|all\s+previous|your\s+instructions)/i,
      ].freeze

      MAX_HITS_BEFORE_BLOCK = 3

      module_function

      # Scan content from a tool result for injection patterns.
      # Fail-closed: severe or high-confidence injection returns Result.err (blocks).
      # Low-confidence: sanitize and continue.
      # @param content [String] raw tool output
      # @param source [String] tool name for logging
      # @return [Result]
      def scan(content, source: "unknown")
        return Result.ok(content) unless content.is_a?(String)

        hits = PATTERNS.select { |p| p.match?(content) }
        return Result.ok(content) if hits.empty?

        severe = SEVERE.count { |p| p.match?(content) }
        Logging.dmesg_log("injection0", message: "source=#{source} hits=#{hits.size} severe=#{severe}")

        if severe.positive? || hits.size >= MAX_HITS_BEFORE_BLOCK
          return Result.err(
            "Prompt injection detected in tool output (source=#{source}). Aborting.",
            category: :security,
          )
        end

        sanitized = hits.reduce(content) { |c, p| c.gsub(p, "[REDACTED:injection_attempt]") }
        Result.ok(sanitized)
      end

      # Quick predicate: is this content safe (no injection patterns)?
      def safe?(content)
        return true unless content.is_a?(String)

        PATTERNS.none? { |p| p.match?(content) }
      end
    end
  end
end
