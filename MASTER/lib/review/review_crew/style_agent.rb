# frozen_string_literal: true

module Master
  module Review
    class ReviewCrew
      class StyleAgent < BaseAgent
        def initialize
          super(name: "StyleAgent")
        end

        # Each check is a pattern and what to say about it. Adding one is a row
        # here, not a method that repeats the finding it builds.
        LINE_CHECKS = [
          { pattern: /[ \t]+\n?\z/, severity: :info, message: "trailing whitespace",
            suggestion: "trim trailing spaces" },
          { pattern: /!\s*important\b/, severity: :warning, message: "!important used",
            suggestion: "prefer cascade and specificity" },
        ].freeze

        def analyze(code, file_path)
          code.each_line.with_index(1) do |line, line_no|
            LINE_CHECKS.each do |check|
              next unless line.match?(check[:pattern])

              add_finding(severity: check[:severity], category: :style, message: check[:message],
                          line: line_no, suggestion: check[:suggestion], file_path:)
            end
          end
          findings
        end
      end
    end
  end
end
