# frozen_string_literal: true

module Master
  module Judge
  module Scan
    module Rules
      class QueryPlanRule < Rule
        def initialize
          super
          @id = "query_plan"
          @description = "Query shapes likely to degrade at scale"
          @severity = :warning
          @rule_tags = %i[PERFORMANCE]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb") && (path.include?("/app/models/") || path.include?("/app/controllers/"))
          findings = []
          code.each_line.with_index(1) do |line, line_number|
            findings << finding(line: line_number, message: "prefer scoped count over full-table count") if line.match?(/\.count\s*$/)
            findings << finding(line: line_number, message: "limit selected columns on wide joins") if line.include?(".joins(") && !line.include?(".select(")
          end
          findings
        end
      end
    end
  end
  end
end
