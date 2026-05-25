# frozen_string_literal: true

module Master
  module Judge
    module Scan
      module Rules
        class BareRescueRule < Rule
          def initialize
            super
            @id = "bare_rescue"
          end

          def check(source, path: nil)
            source.each_line.with_index(1).filter_map do |line, lineno|
              stripped = line.strip
              next unless stripped.match?(/\brescue\b/) && !stripped.start_with?("#")
              next if stripped.match?(/=>/)
              finding(
                line: lineno,
                message: "bare rescue — specify exception type and bind: rescue StandardError => e",
                fix: "rescue StandardError => e"
              )
            end
          end
        end
      end
    end
  end
end
