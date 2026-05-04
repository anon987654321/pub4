# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class NestingDepthRule < Rule
        DEFAULT_DEPTH = 2

        OPEN_KWORDS  = /\b(?:if|unless|case|while|until|for|begin)\b/.freeze
        CLOSE_KWORD  = /\bend\b/.freeze

        def initialize
          super
          @threshold   = Master::Axioms.new.thresholds.dig("method", "max_nesting") || DEFAULT_DEPTH
          @id          = "nesting_depth"
          @description = "Nesting deeper than #{@threshold} — use guard clauses to flatten"
          @severity    = :warning
          @axiom_tags  = [:GUARD_CLAUSES_FIRST]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings    = []
          in_method   = false
          nesting     = 0   # depth relative to method body (0 = top of method)
          over        = false

          code.each_line.with_index(1) do |line, num|
            stripped = line.strip
            next if stripped.start_with?("#")

            if !in_method && stripped.match?(/\bdef \w/)
              in_method = true
              nesting   = 0
              over      = false
              next
            end
            next unless in_method

            opens  = stripped.scan(OPEN_KWORDS).size
            closes = stripped.scan(CLOSE_KWORD).size

            nesting += opens

            if nesting > @threshold && !over
              over = true
              findings << finding(line: num, message: "nesting depth #{nesting} exceeds #{@threshold} — extract method or add guard clause")
            end

            nesting -= closes
            nesting  = [nesting, 0].max

            if nesting <= @threshold
              over = false
            end

            if nesting < 0 || (stripped == "end" && nesting == 0)
              in_method = false
              nesting   = 0
            end
          end
          findings
        end
      end
    end
  end
end
