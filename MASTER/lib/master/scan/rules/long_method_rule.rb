# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class LongMethodRule < Rule
        THRESHOLD = 20

        def initialize
          super
          @id          = "long_method"
          @description = "Methods over #{THRESHOLD} lines should be extracted"
          @severity    = :warning
          @axiom_tags  = [:ONE_JOB]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          findings = []
          method_start = nil
          method_name  = nil
          depth        = 0

          code.each_line.with_index(1) do |line, num|
            if line.match?(/^\s*def /)
              method_start = num
              method_name  = line.match(/def (\w+)/)[1]
              depth        = 1
            elsif method_start
              depth += line.scan(/\bdo\b|\bbegin\b|\bif\b|\bcase\b|\bclass\b|\bmodule\b|\bdef\b/).size
              depth -= line.scan(/\bend\b/).size
              if depth <= 0
                length = num - method_start + 1
                if length > THRESHOLD
                  findings << finding(
                    line: method_start,
                    message: "method #{method_name} is #{length} lines (threshold: #{THRESHOLD})"
                  )
                end
                method_start = nil
              end
            end
          end

          findings
        end
      end
    end
  end
end
