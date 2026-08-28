# frozen_string_literal: true

module Master
  module Review
    module Scan
      # Every write judged by every mechanical rule, on both write paths, with no
      # command to remember. Only what a write *introduces* can block it: a file
      # carrying debt has to stay editable, or the first repair of it is refused.
      #
      # Semantic rules are excluded deliberately. They are 126 of the 225 and
      # cost one LLM call per file, which a per-write gate would pay twice — the
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
            blocking.map { |f| "#{f[:rule]}:#{f[:line]} #{f[:message]}" }.join("; ")
          end
        end

        def self.default
          @default ||= new(rules: InfraHelpers.build_scanner(root: Master::ROOT).rules)
        end

        # A rule that takes an agent is a semantic rule whatever it is called.
        def initialize(rules:)
          @rules = rules.reject { |rule| rule.respond_to?(:set_agent) }
        end

        def verdict(path:, content:)
          if (reason = Master::Core::Constitution.forbidden_file_reason(path))
            return Verdict.new(introduced: [{ rule: :forbidden_file, line: 0, message: reason, severity: :error }])
          end

          before = tally(findings(path:, content: (File.read(path) if File.exist?(path))))
          Verdict.new(introduced: findings(path:, content:).select { |f| (before[key(f)] -= 1).negative? })
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "WriteGuard#verdict", severity: :load_bearing, path:)
          Verdict.new(introduced: [{ rule: :write_guard_error, line: 0, message: e.message, severity: :error }])
        end

        private

        def findings(path:, content:)
          return [] if content.nil?

          @rules.flat_map { |rule| Array(rule.check(content, path: path.to_s)) }
        end

        def tally(list) = list.each_with_object(Hash.new(0)) { |f, acc| acc[key(f)] += 1 }

        def key(finding) = finding[:dedupe_key] || "#{finding[:rule]}:#{finding[:message]}"
      end
    end
  end
end
