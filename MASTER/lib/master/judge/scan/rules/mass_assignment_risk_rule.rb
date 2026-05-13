# frozen_string_literal: true

module Master
  module Judge
  module Scan
    module Rules
      class MassAssignmentRiskRule < Rule
        UPDATE_PARAMS = /\.(?:update|update!|assign_attributes|create|create!|new)\s*\(\s*params\s*[)\.]/.freeze
        UPDATE_PARAMS_BARE = /\.(?:update|update!|assign_attributes)\s*\(\s*params\[/.freeze

        def initialize
          super
          @id          = "mass_assignment_risk"
          @description = "Mass assignment without strong-params .permit — exposes every attribute"
          @severity    = :error
          @rule_tags  = %i[ROBUSTNESS]
        end

        def check(code, path:)
          return [] unless path.include?("/app/controllers/") || path.include?("/app/services/")
          findings = []
          code.each_line.with_index(1) do |line, num|
            next if line.strip.start_with?("#")
            next if line.include?(".permit(")
            findings << finding(line: num,
              message: "mass assignment from params — chain .permit(:allowed, :keys) before update") if line.match?(UPDATE_PARAMS) || line.match?(UPDATE_PARAMS_BARE)
          end
          findings
        end
      end
    end
  end
  end
end
