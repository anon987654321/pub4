# frozen_string_literal: true

require_relative "policy"

module Master
  module Ground
    module SandboxPolicy
      include Policy
      DENY_PATTERNS = [
        /\brm\s+-rf\s+(?:\/|~|\$HOME)\b/,
        /\bsudo\b/,
        /\bmkfs\b/,
        /\bdd\s+if=/,
        /\bchmod\s+-R\s+777\b/,
        /\bchown\s+-R\b/,
        /\bforce-push\b|\bgit\s+push\s+--force/,
        /\b(drop|truncate)\s+(database|table)\b/i,
        /\bshutdown\b|\breboot\b/,
        /\bcurl\b.*\|\s*(?:sh|bash|zsh)/,
      ].freeze

      ASK_PATTERNS = [
        /\bgit\s+push\b/,
        /\bgit\s+reset\s+--hard\b/,
        /\bgit\s+clean\s+-fd/,
        /\bbundle\s+exec\s+rails\s+db:/,
        /\bdelete\b/i,
        /\bdeploy\b/i,
      ].freeze

      ALLOW_PATTERNS = [
        /\Agit\s+(status|diff|log|show|branch)\b/,
        /\A(?:bundle\s+exec\s+)?ruby\s+-c\b/,
        /\A(?:bundle\s+exec\s+)?rspec\b/,
        /\A(?:bundle\s+exec\s+)?rubocop\b/,
        /\A(?:bundle\s+exec\s+)?rails\s+test\b/,
        /\Als\b|\Afind\b|\Agrep\b|\Arg\b/,
      ].freeze

      Decision = Struct.new(:mode, :reason, keyword_init: true) do
        def allow? = mode == :allow
        def ask? = mode == :ask
        def deny? = mode == :deny
      end

      module_function

      def decide(command)
        source = command.to_s.strip
        return Decision.new(mode: :deny, reason: "empty command") if source.empty?
        return Decision.new(mode: :deny, reason: "matched deny pattern") if DENY_PATTERNS.any? { |re| re.match?(source) }
        return Decision.new(mode: :allow, reason: "matched allow pattern") if ALLOW_PATTERNS.any? { |re| re.match?(source) }
        return Decision.new(mode: :ask, reason: "matched ask pattern") if ASK_PATTERNS.any? { |re| re.match?(source) }

        Decision.new(mode: :ask, reason: "unknown command risk")
      end

      def allowed?(command)
        decide(command).allow?
      end

      def brief
        Policy.brief("deny destructive/system commands, ask for pushes/deploy/db/reset, allow read-only git and test/lint")
      end
    end
  end
end
