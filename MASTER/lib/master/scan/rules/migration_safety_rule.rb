# frozen_string_literal: true

module Master
  module Scan
    module Rules
      class MigrationSafetyRule < Rule
        def initialize
          super
          @id = "migration_safety"
          @description = "Flags unsafe migration patterns"
          @severity = :error
          @axiom_tags = %i[ROBUSTNESS]
        end

        def check(code, path:)
          return [] unless path.include?("/db/migrate/") && path.end_with?(".rb")
          findings = []
          code.each_line.with_index(1) do |line, line_number|
            findings << finding(line: line_number, message: "add_reference without foreign_key: true") if line.include?("add_reference") && !line.include?("foreign_key:")
            findings << finding(line: line_number, message: "remove_column is destructive; document safety/backfill path") if line.include?("remove_column")
            findings << finding(line: line_number, message: "find_or_create_by requires backing unique index") if line.include?("find_or_create_by")
          end
          findings
        end
      end
    end
  end
end
