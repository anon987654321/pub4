# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class ImmutableRule < Rule
        UNFROZEN_CONST     = /^\s+[A-Z][A-Z0-9_]+ \s*=\s*(?:"[^"]*"|'[^']*'|\[|\{)(?!.*\.freeze)/.freeze
        MULTILINE_OPEN     = /^\s+[A-Z][A-Z0-9_]+ \s*=\s*[\[{]/.freeze
        STRING_CONTINUATION = /\\\s*$/.freeze
        CLASS_VAR_WRITE = /^\s+@@\w+\s*=(?!=)/.freeze
        GLOBAL_WRITE    = /^\s+\$\w+\s*=(?!=)/.freeze

        def initialize
          super
          @id          = "immutable"
          @description = "Mutable shared state — prefer frozen constants and immutable data flow"
          @severity    = :warning
          @axiom_tags  = [:IMMUTABLE]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          lines = code.lines
          findings = []

          lines.each_with_index do |line, idx|
            num = idx + 1
            next if line.strip.start_with?("#")

            if line.match?(UNFROZEN_CONST)
              if line.match?(MULTILINE_OPEN) && !inline_close?(line)
                findings << finding(line: num, message: "unfrozen constant — append .freeze") unless multiline_frozen?(lines, idx)
              elsif line.match?(STRING_CONTINUATION)
                findings << finding(line: num, message: "unfrozen constant — append .freeze") unless string_continuation_frozen?(lines, idx)
              else
                findings << finding(line: num, message: "unfrozen constant — append .freeze")
              end
            end

            findings << finding(line: num, message: "class variable mutation (@@) — use instance state or inject") if line.match?(CLASS_VAR_WRITE)
            findings << finding(line: num, message: "global variable mutation ($) — eliminate shared global state") if line.match?(GLOBAL_WRITE)
          end

          findings
        end

        private

        def inline_close?(line)
          stripped = line.rstrip
          return true if stripped.end_with?("].freeze", "}.freeze", "].freeze,", "}.freeze,")
          sq = stripped.count("[")
          cq = stripped.count("{")
          (sq > 0 && sq == stripped.count("]")) || (cq > 0 && cq == stripped.count("}"))
        end

        def string_continuation_frozen?(lines, start_line)
          (start_line...lines.size).each do |scan_line|
            return lines[scan_line].include?(".freeze") unless lines[scan_line].match?(STRING_CONTINUATION)
          end
          false
        end

        def multiline_frozen?(lines, start_line)
          line = lines[start_line]
          opener = line.include?("{") ? "{" : "["
          closer = opener == "{" ? "}" : "]"
          depth = 0
          (start_line...lines.size).each do |scan_line|
            depth += lines[scan_line].count(opener) - lines[scan_line].count(closer)
            if depth <= 0
              return lines[scan_line].include?(".freeze")
            end
          end
          false
        end
      end
    end
  end
end
