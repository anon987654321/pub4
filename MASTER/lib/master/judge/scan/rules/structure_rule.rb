# frozen_string_literal: true

module Master
  module Judge
  module Scan
    module Rules
      class StructureRule < Rule
        UNREACHABLE_ELSE = /^\s*return\b[^\n]*\n(?:\s*#[^\n]*\n)*\s*else\b/.freeze
        GUARD_RETURN     = /^\s*if\s+.+\n\s*return\b/.freeze
        FLATTEN_NO_ARG   = /\.flatten\s*(?:\.|$|\))/.freeze
        SINGLE_WHEN      = /\bcase\b/.freeze

        def initialize
          super
          @id          = "structure"
          @description = "Structural anti-patterns — guard clauses, unreachable code, flatten depth"
          @severity    = :warning
          @rule_tags  = [:GUARD_CLAUSES_FIRST]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []

          findings.concat(scan_lines(code, FLATTEN_NO_ARG,
            message: ".flatten without depth arg flattens infinitely — use .flatten(1) unless full depth is intended"))

          findings.concat(check_guard_candidates(code))
          findings.concat(check_single_when(code))
          findings.concat(check_unreachable_else(code))
          findings
        end

        private

        def check_guard_candidates(code)
          findings = []
          lines    = code.lines
          lines.each_with_index do |line, i|
            next unless line.match?(/^\s*if\s+/)
            next_sig = lines[i + 1]&.strip
            next unless next_sig&.start_with?("return")
            findings << finding(line: i + 1, message: "if/return block — invert to guard clause: return X if condition")
          end
          findings
        end

        def check_single_when(code)
          findings = []
          in_case  = false
          when_count = 0
          case_line  = 0

          code.each_line.with_index(1) do |line, num|
            stripped = line.strip
            if stripped.start_with?("case")
              in_case    = true
              when_count = 0
              case_line  = num
            elsif in_case
              when_count += 1 if stripped.start_with?("when")
              if stripped == "end"
                findings << finding(line: case_line, message: "case with one `when` — use if/else") if when_count == 1
                in_case = false
              end
            end
          end
          findings
        end

        def check_unreachable_else(code)
          findings = []
          lines    = code.lines
          lines.each_with_index do |line, i|
            next unless line.strip.start_with?("return")
            j = i + 1
            j += 1 while j < lines.size && lines[j].strip.start_with?("#")
            next unless j < lines.size && lines[j].strip.start_with?("else")
            findings << finding(line: j + 1, message: "else after return is unreachable — remove the else and dedent")
          end
          findings
        end
      end
    end
  end
  end
end
