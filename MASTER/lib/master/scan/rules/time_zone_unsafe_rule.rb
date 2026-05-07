# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class TimeZoneUnsafeRule < Rule
        BARE_TIME_NOW   = /\bTime\.now\b/.freeze
        BARE_DATE_TODAY = /\bDate\.today\b/.freeze
        BARE_DATETIME   = /\bDateTime\.now\b/.freeze

        def initialize
          super
          @id          = "time_zone_unsafe"
          @description = "Bare Time.now / Date.today / DateTime.now ignores app time zone"
          @severity    = :warning
          @axiom_tags  = %i[ROBUSTNESS]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")
          return [] if path.include?("/spec/") || path.include?("/test/")
          findings = []
          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            findings << finding(line: num, message: "Time.now → Time.zone.now / Time.current") if line.match?(BARE_TIME_NOW)
            findings << finding(line: num, message: "Date.today → Date.current") if line.match?(BARE_DATE_TODAY)
            findings << finding(line: num, message: "DateTime.now → Time.zone.now") if line.match?(BARE_DATETIME)
          end
          findings
        end
      end
    end
  end
end
