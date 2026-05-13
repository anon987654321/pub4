# frozen_string_literal: true

module Master
  module Judge
  module Scan
    module Rules
      # Hardcoded threshold constants in scan rules drift silently from rules.yml.
      # Every threshold should be read from Axioms at init time, not baked into a constant.
      # Flags THRESHOLD, MAX_LINES, MIN_LINES, WARN_LINES constants in scan rule files.
      class ThresholdDriftRule < Rule
        DRIFT_CONST = /^\s+(?:THRESHOLD|MAX_LINES|MIN_LINES|WARN_LINES|MAX_PARAMS|MAX_METHODS)\s*=\s*\d+/.freeze

        def initialize
          super
          @id          = "threshold_drift"
          @description = "Hardcoded threshold constant in scan rule — read from Axioms instead"
          @severity    = :warning
          @rule_tags  = [:ONE_SOURCE]
        end

        def check(code, path:)
          return [] unless path.include?("scan/rules") && path.end_with?(".rb")
          scan_lines(code, DRIFT_CONST,
            message: "hardcoded threshold — use Master::Ground::Rules.new.thresholds.dig(...) so rules.yml is the single source")
        end
      end
    end
  end
  end
end
