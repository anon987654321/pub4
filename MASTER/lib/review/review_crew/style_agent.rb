# frozen_string_literal: true

module Master
  module Review
    class ReviewCrew
      class StyleAgent < BaseAgent
        def initialize
          super(name: "StyleAgent")
        end

        def analyze(code, file_path)
          code.each_line.with_index(1) do |line, line_no|
            check_trailing_whitespace(line, line_no, file_path)
            check_important_usage(line, line_no, file_path)
          end
          findings
        end

        private

        def check_trailing_whitespace(line, line_no, file_path)
          return unless line.match?(/[ \t]+\n?\z/)

          add_finding(
            severity: :info,
            category: :style,
            message: "trailing whitespace",
            line: line_no,
            suggestion: "trim trailing spaces",
            file_path: file_path
          )
        end

        def check_important_usage(line, line_no, file_path)
          return unless line.match?(/!\s*important\b/)

          add_finding(
            severity: :warning,
            category: :style,
            message: "!important used",
            line: line_no,
            suggestion: "prefer cascade and specificity",
            file_path: file_path
          )
        end
      end
    end
  end
end
