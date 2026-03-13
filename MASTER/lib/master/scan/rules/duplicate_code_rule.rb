# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class DuplicateCodeRule < Rule
        BLOCK_MIN  = 4
        OCCUR_MIN  = 2

        def initialize
          super
          @id          = "duplicate_code"
          @description = "Duplicate code blocks (>=#{BLOCK_MIN} lines, >=#{OCCUR_MIN} occurrences) violate ONE_SOURCE"
          @severity    = :warning
          @axiom_tags  = [:ONE_SOURCE]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          lines    = code.lines
          findings = []
          seen     = Hash.new(0)

          (0..lines.size - BLOCK_MIN).each do |i|
            block = lines[i, BLOCK_MIN].join
            next if block.strip.empty?
            key = block.gsub(/\s+/, " ").strip
            seen[key] += 1
          end

          seen.each do |block_key, count|
            next if count < OCCUR_MIN
            first_line = code.lines.index { |l|
              block_key.start_with?(l.gsub(/\s+/, " ").strip[0, 20])
            }
            findings << finding(
              line: (first_line || 0) + 1,
              message: "duplicate block appears #{count} times — extract to shared method (ONE_SOURCE)"
            )
          end

          findings.first(5)
        end
      end
    end
  end
end
