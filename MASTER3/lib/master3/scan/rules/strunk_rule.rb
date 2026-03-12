# frozen_string_literal: true

module Master3
  module Scan
    module Rules
      # StrunkRule — flags hedge words and preamble phrases in Ruby comments.
      # Violations drive Sweep convergence: prose quality has a measurable score.
      class StrunkRule < Rule
        HEDGES = /\b(simply|just|basically|essentially|obviously|clearly|
                      easily|needless(?:ly)?|straightforward(?:ly)?)\b/ix.freeze

        PREAMBLES = /
          \#.*(?:
            I'?d\s+be\s+happy\s+to |
            great\s+question        |
            certainly[,.]?         |
            of\s+course[,.]?       |
            I\s+think\s+that       |
            I\s+believe\s+that     |
            please\s+note\s+that   |
            keep\s+in\s+mind       |
            feel\s+free\s+to       |
            it'?s\s+worth\s+noting
          )
        /ix.freeze

        def initialize
          super
          @id          = "strunk"
          @description = "Hedge words and preamble phrases in comments reduce clarity"
          @severity    = :warning
          @axiom_tags  = [:STRUNK_WHITE]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          code.each_line.with_index(1).flat_map { |line, num|
            next [] unless line.include?("#")

            findings = []
            findings << finding(line: num, message: "hedge in comment: #{line.strip}") if line.match?(HEDGES)
            findings << finding(line: num, message: "preamble in comment: #{line.strip}") if line.match?(PREAMBLES)
            findings
          }
        end
      end
    end
  end
end
