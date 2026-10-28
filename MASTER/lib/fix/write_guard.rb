# frozen_string_literal: true

require_relative "../configuration_guard"

module Master
  module Fix
    # Every write judged by every mechanical rule, on both write paths, with no
    # command to remember. Only what a write *introduces* can block it: a file
    # carrying debt has to stay editable, or the first repair of it is refused.
    #
    # Semantic rules are excluded deliberately. They are 126 of the 225 and
    # cost one LLM call per file, which a per-write check would pay twice — the
    # before and the after. They belong to the per-turn pass, not here.
    #
    # The mechanical half costs 1.2 ms on a 5-line file and 286 ms on a
    # 538-line one, both scans included. A new file pays for one.
    class WriteGuard
      BLOCKING = %i[veto critical error].freeze

      Verdict = Data.define(:introduced) do
        def blocking = introduced.select { |f| BLOCKING.include?(f[:severity]) }
        def blocked? = !blocking.empty?

        def reason
          blocking.map { |f| "#{f[:law]}:#{f[:line]} #{f[:message]}" }.join("; ")
        end
      end

      def self.default
        require File.join(Master::ROOT, "law", "definition") unless defined?(::Law)
        ::Law.load_all(File.join(Master::ROOT, "law")) if ::Law.definitions.empty?
        digest = ::Law::Contract.digest
        return @default if @default && @default_digest == digest

        scanner = Master::Fix::Scanner.build(root: Master::ROOT)
        laws = scanner.laws
        @default = new(laws:)
        @default_digest = digest
        @default
      end

      def self.reset_default!
        @default = nil
        @default_digest = nil
      end

      # A rule that takes an agent is a semantic rule whatever it is called.
      def initialize(laws:)
        @laws = laws.reject { |rule| rule.respond_to?(:set_agent) }
      end

      # A sacred path is refused to an automated writer before its content is
      # judged. automated: false is the hand edit an agent makes for the operator
      # (tools/law_check_edit.rb), which, like a person's commit, may change one.
      def verdict(path:, content:, automated: true)
        law, reason = refusal(path:, content:, automated:)
        return Verdict.new(introduced: [{ law:, line: 0, message: reason, severity: :error }]) if reason

        before = tally(findings(path:, content: (File.read(path) if File.exist?(path))))
        Verdict.new(introduced: findings(path:, content:).select { |f| (before[key(f)] -= 1).negative? })
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "WriteGuard#verdict", severity: :load_bearing, path:)
        Verdict.new(introduced: [{ law: :write_guard_error, line: 0, message: e.message, severity: :error }])
      end

      private

      # [law, reason] for a write refused before its findings are counted, or nil.
      def refusal(path:, content:, automated:)
        if automated && (reason = Master::Core::Constitution::Paths.write_refusal(path))
          return [:sacred_path, reason]
        end
        if (reason = Master::Core::Constitution.forbidden_file_reason(path))
          return [:forbidden_file, reason]
        end

        reason = Master::ConfigurationGuard.validate(path:, content:)
        [:configuration_invariant, reason] if reason
      end

      def findings(path:, content:)
        return [] if content.nil?

        @laws.flat_map { |rule| Array(rule.check(content, path: path.to_s)) }
      end

      def tally(list) = list.each_with_object(Hash.new(0)) { |f, acc| acc[key(f)] += 1 }

      def key(finding) = finding[:dedupe_key] || "#{finding[:law]}:#{finding[:message]}"
    end
  end
end
