# frozen_string_literal: true

require "open3"

module Master
  module Judge
  module Scan
    module Rules
      class TodoDebtRule < Rule
        DEBT_TAGS = /\b(?:TODO|FIXME|XXX|HACK|REFACTOR|REVIEW|BUG)\b/.freeze
        STALE_DAYS = 90

        def initialize
          super
          @id          = "todo_debt"
          @description = "TODO/FIXME comment older than #{STALE_DAYS} days — resolve or delete"
          @severity    = :info
          @rule_tags  = %i[BE_CONCISE]
        end

        def check(code, path:)
          return [] unless File.exist?(path)
          findings = []
          code.each_line.with_index(1) do |line, num|
            next unless line.include?("#") && line.match?(DEBT_TAGS)
            age = blame_age_days(path, num)
            next unless age && age > STALE_DAYS
            findings << finding(line: num, 
message: "debt tag #{age} days old — resolve or delete: #{line.strip[0, 80]}")
          end
          findings
        rescue StandardError
          []
        end

        private

        def blame_age_days(path, line)
          out, _, status = Open3.capture3("git", "-C", File.dirname(path), "blame", "-L", "#{line},#{line}", 
"--porcelain", File.basename(path))
          return unless status.success?
          ts = out[/^author-time (\d+)/, 1]&.to_i
          return unless ts
          ((Time.now.to_i - ts) / 86_400).to_i
        end
      end
    end
  end
  end
end
