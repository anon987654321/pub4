# frozen_string_literal: true

require "json"
require_relative "../review/scan/law_health"

module Master
  module Fix
    # Detector matrix: law enforcement and detection surface mapping.
    # External LLMs and agents need to know which laws are scannable,
    # semantic, conduct-only, or measurement-only before attempting repair.
    module ProtocolDetectorMatrix
      module_function

      # Build the detector matrix for all laws.
      def matrix(laws)
        laws.each_with_object({}) do |law, h|
          h[law.id.to_s] = entry(law)
        end
      end

      # One law's detector entry: what surfaces it operates on, how it enforces.
      def entry(law)
        {
          "id" => law.id.to_s,
          "scannable" => law.respond_to?(:scannable?) && law.scannable?,
          "semantic" => law.respond_to?(:semantic?) && law.semantic?,
          "conduct" => law.respond_to?(:practice) && !law.practice.to_s.empty?,
          "detector_kind" => detector_kind(law),
          "enforcement" => Master::Review::Scan::LawHealth.enforcement(law).to_s,
          "measurement_mode" => Master::Review::Scan::LawHealth.measurement_mode?(law),
          "severity" => law.respond_to?(:severity) ? law.severity.to_s : "unknown",
          "applies_to" => Array(law.respond_to?(:applies_to) ? law.applies_to : []),
          "path_exclude" => detector_paths(law),
          "calibration" => Master::Review::Scan::LawHealth.calibration(law)
        }
      end

      # What kind of detector this law uses.
      def detector_kind(law)
        return "semantic" if law.respond_to?(:semantic?) && law.semantic?
        return "conduct" if law.respond_to?(:practice) && !law.practice.to_s.empty?
        return "deterministic" if law.respond_to?(:scannable?) && law.scannable?

        "unknown"
      end

      def detector_paths(law)
        Array(law.respond_to?(:path_exclude) ? law.path_exclude : []).map do |path|
          path.is_a?(Regexp) ? path.source : path.to_s
        end
      end

      # Summary statistics for the matrix.
      def summary(matrix)
        {
          "total_laws" => matrix.size,
          "scannable_laws" => matrix.values.count { |e| e["scannable"] },
          "semantic_laws" => matrix.values.count { |e| e["semantic"] },
          "conduct_laws" => matrix.values.count { |e| e["conduct"] },
          "measurement_mode_laws" => matrix.values.count { |e| e["measurement_mode"] },
          "blocking_laws" => matrix.values.count { |e| e["enforcement"] == "blocking" }
        }
      end
    end
  end
end
