# frozen_string_literal: true

module Master
  module Ground
    module Policy
      module Sandbox
        # Found by adversarial testing (matching OpenCrabs' security-eval
        # corpus pattern), not hypothetically: the original -rf-only pattern
        # let `rm -fr ~`, `rm --recursive --force ~`, and any other flag
        # ordering straight through as "ask" instead of "deny" -- same
        # command, different flag order, real gap. DANGEROUS_RM_TARGET below
        # replaces the single-regex approach with actual flag parsing so
        # order/form can't matter. Also added: a classic fork bomb, wget
        # (curl's pipe-to-shell pattern only covered curl), and truncating a
        # raw block device via redirection -- none of those had any pattern
        # at all. The (?<q>["']?)...\k<q> wrapper was added after the
        # permanent test corpus caught `rm -rf "$HOME"` (quoted, still
        # expands under bash) slipping through as "ask" -- the bare pattern
        # only matched an unquoted target.
        DANGEROUS_RM_TARGET = /\brm\s+(?<flags>[\w-]+(?:\s+[\w-]+)*)\s+(?<q>["']?)(?:\/|~|\$HOME)\k<q>(?=\s|\z)/.freeze
        FORK_BOMB = /:\s*\(\s*\)\s*\{[^}]*:\s*\|\s*:/.freeze
        DEVICE_REDIRECT = %r{(?:^|\s):?>\s*/dev/(?:sd|disk|hd|nvme|rdisk)}.freeze

        DENY_PATTERNS = [
          /\bsudo\b/,
          /\bmkfs\b/,
          /\bdd\s+if=/,
          /\bchmod\s+-R\s+777\b/,
          /\bchown\s+-R\b/,
          /\bforce-push\b|\bgit\s+push\s+--force/,
          /\b(drop|truncate)\s+(database|table)\b/i,
          /\bshutdown\b|\breboot\b/,
          /\b(?:curl|wget)\b.*\|\s*(?:sh|bash|zsh)/,
          FORK_BOMB,
          DEVICE_REDIRECT,
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

        Decision = Struct.new(:mode, :reason, :recognised, keyword_init: true) do
          def allow? = mode == :allow
          def ask? = mode == :ask
          def deny? = mode == :deny

          # Two unrelated things answer :ask. A command matching ASK_PATTERNS --
          # a push, a hard reset, a deploy -- is one this policy recognises by
          # name and wants a person for. Everything it has no pattern for answers
          # :ask as well, and that is most real commands. Only the first is worth
          # stopping someone for, and a caller that cannot tell the two apart has
          # to treat both as allow to stay usable.
          def recognised_ask? = ask? && !!recognised
        end

        module_function

        def decide(command)
          source = command.to_s.strip
          return Decision.new(mode: :deny, reason: "empty command") if source.empty?
          return Decision.new(mode: :deny, reason: "recursive+force rm of a dangerous path") if dangerous_rm?(source)
          return Decision.new(mode: :deny, reason: "matched deny pattern") if DENY_PATTERNS.any? { |re| source.match?(re) }
          return Decision.new(mode: :ask, reason: "matched ask pattern", recognised: true) if ASK_PATTERNS.any? { |re| source.match?(re) }
          return Decision.new(mode: :allow, reason: "matched allow pattern") if ALLOW_PATTERNS.any? { |re| source.match?(re) }

          Decision.new(mode: :ask, reason: "unknown command risk", recognised: false)
        end

        # Flag-parses rather than pattern-matching flag order/form, so
        # `-rf`, `-fr`, `-Rf`, `--recursive --force`, `--force --recursive`,
        # and `-r -f` are all equally caught regardless of how they're
        # written -- see DANGEROUS_RM_TARGET's comment for why this exists.
        def dangerous_rm?(source)
          match = source.match(DANGEROUS_RM_TARGET)
          return false unless match

          flags = match[:flags]
          recursive = flags.match?(/(?:\A|\s)-\w*[rR]\w*(?:\s|\z)/) || flags.include?("--recursive")
          force = flags.match?(/(?:\A|\s)-\w*f\w*(?:\s|\z)/) || flags.include?("--force")
          recursive && force
        end

        def allowed?(command)
          decide(command).allow?
        end

        # Ground::Policy was a module holding one method, whose stated goal was
        # "reduce duplication across the *Policy modules". One of the four ever called
        # it, for one string, and the namespace those four now share expresses the
        # grouping the helper was reaching for. Folded here — which is also what pays
        # for the two lines of nesting this regroup added to each file.
        def brief
          "#{Policy.name}: deny destructive/system commands, ask for pushes/deploy/db/reset, " \
            "allow read-only git and test/lint"
        end
      end
    end
  end
end
