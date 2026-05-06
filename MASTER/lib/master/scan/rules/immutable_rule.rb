# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class ImmutableRule < Rule
        UNFROZEN_CONST     = /^\s+[A-Z][A-Z0-9_]+ \s*=\s*(?:"[^"]*"|'[^']*'|\[|\{)(?!.*(?:\.freeze|\.min|\.max|\.count|\.size|\.length|\.sum|\.to_i|\.to_f)\b)/.freeze
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

          lines.each_with_index do |line, line_index|
            line_number = line_index + 1
            next if line.strip.start_with?("#")

            if line.match?(UNFROZEN_CONST)
              if line.match?(MULTILINE_OPEN) && !inline_close?(line)
                findings << finding(line: line_number, 
message: "unfrozen constant — append .freeze") unless multiline_frozen?(
lines, line_index)
              elsif line.match?(STRING_CONTINUATION)
                findings << finding(line: line_number, 
message: "unfrozen constant — append .freeze") unless string_continuation_frozen?(
lines, line_index)
              else
                findings << finding(line: line_number, message: "unfrozen constant — append .freeze")
              end
            end

            findings << finding(line: line_number, 
message: "class variable mutation (@@) — use instance state or inject") if line.match?(CLASS_VAR_WRITE)
            findings << finding(line: line_number, 
message: "global variable mutation ($) — eliminate shared global state") if line.match?(GLOBAL_WRITE)
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
          (start_line...lines.size).each do |current_line|
            return lines[current_line].include?(".freeze") unless lines[current_line].match?(STRING_CONTINUATION)
          end
          false
        end

        def multiline_frozen?(lines, start_line)
          line   = lines[start_line]
          opener = line.include?("{") ? "{" : "["
          closer = opener == "{" ? "}" : "]"
          depth  = 0
          (start_line...lines.size).each do |current_line|
            depth += lines[current_line].count(opener) - lines[current_line].count(closer)
            return lines[current_line].include?(".freeze") if depth <= 0
          end
          false
        end
      end
    end
  end
end
