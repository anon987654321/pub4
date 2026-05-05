# frozen_string_literal: true

module Master
  module Security
    class InjectionGuard
      PATTERNS = [
        /ignore (?:previous|all|your) instructions/i,
        /disregard (?:your )?(?:system )?prompt/i,
        /you are now (?:a|an|in)/i,
        /pretend (?:to be|you are|you're)/i,
        /new instructions:/i,
        /\[SYSTEM\]/i,
        /###\s*SYSTEM/i,
        /(?:act|behave|respond) as (?:if )?(?:you (?:are|were)|a|an) (?!assistant|helpful)/i,
        /override (?:your )?(?:safety|guidelines|rules|instructions)/i,
/forget (?:everything|all|your)/i,
/override (?:axiom|principle|rule)/i,
/disregard (?:axiom|principle|rule|safety)/i,
/new system prompt/i,

        /jailbreak/i,
      ].freeze

      # Shell-injection pattern checked separately (multiline, heavier regex).
      SHELL_INJECTION_RE = /```(?:bash|sh|zsh|shell)\n.*?(?:rm\s+-rf|curl\b.*?\|\s*(?:bash|sh)\b|wget\b.*?\|\s*(?:bash|sh)\b)/im.freeze

      def scan(content)
        hits = PATTERNS.select { |p| content.match?(p) }
        hits << SHELL_INJECTION_RE if content.match?(SHELL_INJECTION_RE)
        return Result.ok(:clean) if hits.empty?
        Result.err("injection detected: #{hits.size} pattern(s) matched", category: :validation)
      end

      def clean!(content)
        cleaned = PATTERNS.reduce(content) { |c, p| c.gsub(p, "[REDACTED]") }
        Result.ok(cleaned)
      end
    end
  end
end
