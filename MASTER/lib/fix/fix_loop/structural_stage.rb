# frozen_string_literal: true

require_relative "../../../tools/cohesion"

module Master
  module Fix
    class FixLoop
      module StructuralStage
        RULE_ID = "STRUCTURAL_COHESION"

        def structural_findings(files:)
          directories = files.filter_map do |path|
            next unless path.to_s.end_with?(".rb")
            File.dirname(path)
          end.uniq

          directories.flat_map do |dir|
            Operator::Cohesion.plans_for(dir).map do |plan|
              {
                rule: RULE_ID,
                laws: %w[SINGULARITY ABSTRACTION DENSITY PROXIMITY KISS],
                source: "cohesion",
                file: relative_path(plan.fetch(:files).first, dir),
                line: 1,
                message: structural_message(dir, plan),
                evidence: plan.fetch(:evidence, {}),
              }
            end
          end
        rescue StandardError => e
          raise "structural cohesion observation failed: #{e.class}: #{e.message}"
        end

        private

        def relative_path(file, dir)
          File.join(dir, file)
        end

        def structural_message(dir, plan)
          files = plan.fetch(:files).join(", ")
          external = Array(plan.dig(:evidence, :external_references))
          refs = external.map { |row| "#{row[:file]}:#{row[:symbols].join(",")}" }.first(8)
          evidence = refs.empty? ? "no external Ruby references found" : "external references: #{refs.join("; ")}"
          "#{plan.fetch(:plan)} #{plan.fetch(:family)} in #{dir}: #{files}; #{evidence}; repair and recheck references before consolidation"
        end
      end
    end
  end
end
