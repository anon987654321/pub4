# frozen_string_literal: true

module Master3
  module Security
    class InjectionGuard
      PATTERNS = [
        /ignore previous instructions/i,
        /disregard your (system )?prompt/i,
        /you are now/i,
        /pretend (to be|you are)/i,
        /new instructions:/i,
        /\[SYSTEM\]/i,
        /###\s*SYSTEM/i
      ].freeze

      def scan(content)
        hits = PATTERNS.select { |p| content.match?(p) }
        return Result.ok(:clean) if hits.empty?
        Result.err("injection detected: #{hits.size} pattern(s) matched", category: :validation)
      end

      # Returns self so callers can chain; mutates nothing (returns cleaned string via Result).
      def clean!(content)
        cleaned = PATTERNS.reduce(content) { |c, p| c.gsub(p, "[REDACTED]") }
        Result.ok(cleaned)
      end
    end
  end
end
