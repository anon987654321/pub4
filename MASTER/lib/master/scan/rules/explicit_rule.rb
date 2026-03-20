# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # ExplicitRule — detects implicit/opaque patterns that violate EXPLICIT.
      # Flags: bare rescue, implicit return of nil, magic number literals,
      # single-letter variable names outside loops, and undefined method patterns.
      class ExplicitRule < Rule
        RESCUE_NIL   = /rescue\s+nil\b/.freeze
        MAGIC_NUM    = /[^:]\b([2-9]\d{2,}|[1-9]\d{3,})\b(?!\s*[#=])/.freeze
        OPAQUE_VAR   = /^\s+[a-z]\s*=(?!=)/.freeze        # x = ... (not x == or x +=)
        IMPLICIT_NIL = /def\s+\w+[^;]*\n(?:\s*#[^\n]*\n)*\s*end/.freeze  # empty method body

        def initialize
          super
          @id          = "explicit"
          @description = "Implicit, opaque patterns — prefer explicit contracts"
          @severity    = :warning
          @axiom_tags  = [:EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          findings = []
          code.each_line.with_index(1) do |line, num|
            findings << finding(line: num, message: "bare rescue hides errors — name the exception class or propagate") if line.match?(RESCUE_NIL)
            findings << finding(line: num, message: "magic number — extract to a named constant")                if line.match?(MAGIC_NUM) && !line.strip.start_with?("#")
            findings << finding(line: num, message: "single-letter variable obscures intent — use a descriptive name") if line.match?(OPAQUE_VAR) && !in_loop_context?(code, num)
          end
          findings
        end

        private

        def in_loop_context?(code, target_line)
          lines = code.lines
          ((target_line - 4)..(target_line - 1)).any? do |i|
            next false unless i >= 0 && i < lines.size
            lines[i].match?(/\b(?:each|map|times|upto|downto|step|for\s+\w)\b/)
          end
        end
      end
    end
  end
end
