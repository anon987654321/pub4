# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class DeadCodeRule < Rule
        EMPTY_RESCUE = /rescue\s+\w[\w:]*(?:\s*=>\s*\w+)?\s*\n\s*end/.freeze
        CONST_DEF    = /^\s*([A-Z][A-Z0-9_]{2,})\s*=(?!=)/.freeze

        def initialize
          super
          @id          = "dead_code"
          @description = "Dead constants and empty rescue blocks"
          @severity    = :warning
          @axiom_tags  = [:EXPLICIT]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          line_rescue_findings(code) + dead_constants(code)
        end

        private

        def line_rescue_findings(code)
          findings = []
          lines    = code.lines
          lines.each_with_index do |line, i|
            next unless line.match?(/^\s*rescue\b/)
            next_stripped = lines[i + 1]&.strip
            if next_stripped == "end"
              findings << finding(line: i + 1, message: "empty rescue block swallows errors silently — log or re-raise")
            end
          end
          findings
        end

        def dead_constants(code)
          findings = []
          lines    = code.lines
          lines.each_with_index do |line, i|
            m = line.match(CONST_DEF)
            next unless m

            const = m[1]
            next if code.scan(/\b#{Regexp.escape(const)}\b/).size > 1

            findings << finding(line: i + 1, message: "#{const} is defined but never referenced — remove it")
          end
          findings
        end
      end
    end
  end
end
