# frozen_string_literal: true

module Master
  module Judge
    module Scan
      module Rules
        # Bridges rules.yml veto_patterns into the scanner (constitution.rb also checks writes).
        class VetoPatternRule < Rule
          def self.auto_build? = false

          def initialize(root: Master::ROOT)
            super()
            @id = "veto_patterns"
            @description = "Unconditional merge blockers from rules.yml veto_patterns"
            @severity = :veto
            @auto_fix = false
            @patterns = load_patterns(root)
          end

          def check(code, path:)
            return [] if @patterns.empty?

            @patterns.flat_map do |name, spec|
              detect = spec["detect"]
              next [] unless detect

              regex = detect.is_a?(String) ? Regexp.new(detect) : detect
              scan_lines(code, regex, message: "veto: #{name} — #{spec["apply"] || "blocked"}")
            end
          end

          private

          def load_patterns(root)
            data = Master.load_yaml(File.join(root, "data", "rules.yml")) || {}
            data.fetch("veto_patterns", {})
          rescue StandardError
            {}
          end
        end
      end
    end
  end
end