# frozen_string_literal: true

module Master
  module Judge
  module Scan
    module Rules
      class HotwirePatternRule < Rule
        def initialize
          super
          @id = "hotwire_pattern"
          @description = "Flags heavy Hotwire anti-patterns"
          @severity = :warning
          @rule_tags = %i[PERFORMANCE]
        end

        def check(code, path:)
          return [] unless path.end_with?(".erb") || path.end_with?(".js")
          findings = []
          code.each_line.with_index(1) do |line, line_number|
            findings << finding(line: line_number, message: "prefer turbo-frame/turbo-stream over manual fetch") if line.include?("fetch(")
            findings << finding(line: line_number, message: "form is missing turbo-frame binding") if line.include?("form_with") && !line.include?("turbo_frame")
          end
          findings
        end
      end
    end
  end
  end
end
