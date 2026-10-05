# frozen_string_literal: true

require "json"
require_relative "../review/scan/rule_health"

module Master
  module Fix
    # Detector matrix: rule enforcement and detection surface mapping.
    # External LLMs and agents need to know which rules are scannable,
    # semantic, conduct-only, or measurement-only before attempting repair.
    module ProtocolDetectorMatrix
      module_function

      # Build the detector matrix for all rules.
      def matrix(rules)
        rules.each_with_object({}) do |rule, h|
          h[rule.id.to_s] = entry(rule)
        end
      end

      # One rule's detector entry: what surfaces it operates on, how it enforces.
      def entry(rule)
        {
          "id" => rule.id.to_s,
          "scannable" => rule.respond_to?(:scannable?) && rule.scannable?,
          "semantic" => rule.respond_to?(:semantic?) && rule.semantic?,
          "conduct" => rule.respond_to?(:practice) && !rule.practice.to_s.empty?,
          "detector_kind" => detector_kind(rule),
          "enforcement" => Master::Review::Scan::RuleHealth.enforcement(rule).to_s,
          "measurement_mode" => Master::Review::Scan::RuleHealth.measurement_mode?(rule),
          "severity" => rule.respond_to?(:severity) ? rule.severity.to_s : "unknown",
          "applies_to" => Array(rule.respond_to?(:applies_to) ? rule.applies_to : []),
          "path_exclude" => Array(rule.respond_to?(:path_exclude) ? rule.path_exclude : []),
          "calibration" => Master::Review::Scan::RuleHealth.calibration(rule)
        }
      end

      # What kind of detector this rule uses.
      def detector_kind(rule)
        return "semantic" if rule.respond_to?(:semantic?) && rule.semantic?
        return "conduct" if rule.respond_to?(:practice) && !rule.practice.to_s.empty?
        return "deterministic" if rule.respond_to?(:scannable?) && rule.scannable?

        "unknown"
      end

      # Summary statistics for the matrix.
      def summary(matrix)
        {
          "total_rules" => matrix.size,
          "scannable_rules" => matrix.values.count { |e| e["scannable"] },
          "semantic_rules" => matrix.values.count { |e| e["semantic"] },
          "conduct_rules" => matrix.values.count { |e| e["conduct"] },
          "measurement_mode_rules" => matrix.values.count { |e| e["measurement_mode"] },
          "blocking_rules" => matrix.values.count { |e| e["enforcement"] == "blocking" }
        }
      end
    end
  end
end
