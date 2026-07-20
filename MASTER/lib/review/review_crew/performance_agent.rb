# frozen_string_literal: true

module Master
  module Review
    class ReviewCrew
      class PerformanceAgent < BaseAgent
        def initialize
          super(name: "PerformanceAgent")
        end

        def analyze(code, file_path)
          lines = code.lines
          check_file_length(lines, file_path)
          check_long_lines(lines, file_path)
          findings
        end

        private

        def check_file_length(lines, file_path)
          return unless lines.size > 300

          add_finding(
            severity: :warning,
            category: :performance,
            message: "file is #{lines.size} lines",
            line: 1,
            suggestion: "split the file at responsibility boundaries",
            file_path: file_path
          )
        end

        def check_long_lines(lines, file_path)
          lines.each_with_index do |line, idx|
            next if line.length <= 120

            add_finding(
              severity: :info,
              category: :performance,
              message: "line #{line.chomp.length} chars",
              line: idx + 1,
              suggestion: "wrap the line or extract a helper",
              file_path: file_path
            )
          end
        end
      end
    end
  end
end
