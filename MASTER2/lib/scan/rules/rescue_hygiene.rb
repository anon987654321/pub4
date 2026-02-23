# frozen_string_literal: true

module MASTER
  module Scan
    module Rules
      # RescueHygiene — flags bare-rescue, rescue-nil, and unused rescue variables.
      # Migrated from Review::Scanner::CHECKS.
      module RescueHygiene
        include Scan::Rule

        CHECKS = {
          rescue_without_type: {
            pattern:  /rescue\s*$/,
            message:  "Bare rescue catches all exceptions - use StandardError",
            severity: :minor,
          }.freeze,
          rescue_nil: {
            pattern:  /rescue\s+nil\b/,
            message:  "rescue nil swallows all exceptions silently — use rescue StandardError",
            severity: :major,
          }.freeze,
          unused_rescue_var: {
            pattern:  /rescue(?:\s+\w+)?\s*=>\s*e\s*(?:;\s*(?:nil|\{\}|\[\])|[\r\n]\s*(?:nil|end|\{\}|\[\]))/,
            message:  "Rescue captures 'e' but body is empty — drop => e if variable unused",
            severity: :minor,
          }.freeze,
        }.freeze

        def self.check(code, path: nil)
          findings = []

          code.each_line.with_index(1) do |line_text, line_num|
            CHECKS.each do |check_name, check_def|
              next unless line_text.match?(check_def[:pattern])

              findings << {
                rule:      check_name,
                name:      check_name,
                message:   check_def[:message],
                line:      line_num,
                severity:  check_def[:severity],
                autofix:   false,
                principle: nil,
              }
            end
          end

          findings
        end
      end
    end
  end
end
