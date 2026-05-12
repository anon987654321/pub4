# frozen_string_literal: true

module Master
  module Judge
  module Security
    class InjectionGuard
      DATA_PATH = File.join(Master::ROOT, "data", "injection_patterns.yml")

      DEFAULTS = {
        prompt_injection: [
          /ignore (?:previous|all|your) instructions/i,
          /disregard (?:your )?(?:system )?prompt/i,
          /you are now (?:a|an|in)/i,
          /pretend (?:to be|you are|you're)/i,
          /new instructions:/i,
          /\[SYSTEM\]/i,
          /###\s*SYSTEM/i,
          /(?:act|behave|respond) as (?:if )?(?:you (?:are|were)|a|an) (?!assistant|helpful)/i,
          /override (?:your )?(?:safety|guidelines|rules|instructions)/i,
          /jailbreak/i,
          /forget (?:everything|all|your)/i,
          /override (?:axiom|principle|rule)/i,
          /disregard (?:axiom|principle|rule|safety)/i,
          /new system prompt/i,
        ].freeze,
        shell_injection: /```(?:bash|sh|zsh|shell)\n.*?(?:rm\s+-rf|curl\b.*?\|\s*(?:bash|sh)\b|wget\b.*?\|\s*(?:bash|sh)\b)/im.freeze,
      }.freeze

      ALLOWLIST_TOKEN = /\AMASTER_TRUSTED:[A-Za-z0-9]{16,}/.freeze

      def initialize(mode: :permissive)
        @mode     = mode
        @patterns = load_or_default
      end

      def scan(content)
        hits = @patterns[:prompt_injection].select { |p| content.match?(p) }
        hits << @patterns[:shell_injection] if content.match?(@patterns[:shell_injection])

        if hits.empty?
          return Result.ok(:clean) if @mode == :permissive
          return Result.ok(:clean) if content.match?(ALLOWLIST_TOKEN)
          return Result.err("default_deny: no allowlist token; rejecting unmatched input", category: :validation)
        end
        Result.err("injection detected: #{hits.size} pattern(s) matched", category: :validation)
      end

      def safe?(text)
        scan(text.to_s).ok?
      end

      def clean!(content)
        cleaned = @patterns[:prompt_injection].reduce(content) { |c, p| c.gsub(p, "[REDACTED]") }
        Result.ok(cleaned)
      end

      private

      def load_or_default
        return DEFAULTS unless File.exist?(DATA_PATH)
        data = Master.load_yaml(DATA_PATH) || {}
        prompt = (data["prompt_injection"] || []).map { |s| Regexp.new(s, Regexp::IGNORECASE) }
        shell  = data.dig("shell_injection", "multiline_pattern")
        {
          prompt_injection: prompt.empty? ? DEFAULTS[:prompt_injection] : prompt.freeze,
          shell_injection:  shell ? Regexp.new(shell, 
Regexp::MULTILINE | Regexp::IGNORECASE) : DEFAULTS[:shell_injection],
        }
      rescue StandardError
        DEFAULTS
      end
    end
  end
  end
end
