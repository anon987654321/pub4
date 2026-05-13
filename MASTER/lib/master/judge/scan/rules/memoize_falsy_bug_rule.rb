# frozen_string_literal: true

module Master
  module Judge
  module Scan
    module Rules
      class MemoizeFalsyBugRule < Rule
        # @x ||= expr where expr can return false/nil — re-evaluates every call
        OR_EQUALS_BOOL = /@\w+\s*\|\|=\s*(?:false|nil|.*?\.\w+\?)/.freeze
        OR_EQUALS_FIND = /@\w+\s*\|\|=\s*.*?\.(?:find|find_by|first|detect|presence)\b/.freeze

        def initialize
          super
          @id          = "memoize_falsy_bug"
          @description = "@x ||= memoization that may return false/nil — caller pays cost every time"
          @severity    = :warning
          @rule_tags  = %i[PERFORMANCE EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            findings << finding(line: num,
              message: "@var ||= boolean/predicate — use defined?(@var) ? @var : (@var = expr)") if line.match?(OR_EQUALS_BOOL)
            findings << finding(line: num,
              message: "@var ||= find/find_by — nil result re-queries every call; cache via defined?") if line.match?(OR_EQUALS_FIND)
          end
          findings
        end
      end
    end
  end
  end
end
