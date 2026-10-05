# frozen_string_literal: true

module Master
  module Review
    module Scan
      # Reads detector-health policy from laws.yml and projects it onto findings.
      # Measurement-only findings remain visible to the scanner but do not enter
      # the automatic repair threshold.
      module RuleHealth
        module_function

        def measurement_only_ids
          config = Master.law("detection_calibration")
          rows = config.fetch("measurement_only", {})
          ids = case rows
               when Hash then rows.keys
               when Array then rows.flat_map { |row| row.is_a?(Hash) ? row.keys : Array(row) }
               else []
               end
          ids.map(&:to_s).uniq.freeze
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "rule_health.measurement_only_ids")
          raise "rule health policy unreadable: #{e.class}: #{e.message}"
        end

        def measurement_mode?(rule)
          return false unless rule.respond_to?(:id)

          measurement_only_ids.include?(rule.id.to_s) ||
            (rule.respond_to?(:measurement_mode) && rule.measurement_mode == true)
        end

        def enforcement(rule)
          return :measurement if measurement_mode?(rule)

          severity = rule.respond_to?(:severity) ? rule.severity.to_s : "warning"
          %w[error critical veto].include?(severity) ? :blocking : :advisory
        end

        def user_message(rule)
          case enforcement(rule)
          when :measurement then "#{rule.id}: measured only — non-blocking"
          when :blocking then "#{rule.id}: blocking rule"
          else "#{rule.id}: advisory finding"
          end
        end

        def calibration(rule)
          return {} unless rule.respond_to?(:id)

          id = rule.id.to_s
          config = Master.law("detection_calibration").fetch("measurement_only", {}).fetch(id, {})
          {
            "measurement_mode" => measurement_mode?(rule),
            "enforcement" => enforcement(rule).to_s,
            "reason" => config["reason"]
          }.compact
        rescue KeyError
          {
            "measurement_mode" => measurement_mode?(rule),
            "enforcement" => enforcement(rule).to_s
          }
        end

        # Keep the original severity as evidence, while giving the repair path
        # an honest effective severity for measurement-only findings.
        def annotate(finding)
          return finding unless finding.respond_to?(:to_h)

          data = finding.to_h.transform_keys(&:to_sym)
          id = (data[:rule] || data[:rule_id]).to_s
          return finding unless measurement_only_ids.include?(id)

          data[:original_severity] ||= data[:severity]
          data[:severity] = :info
          data[:enforcement] = "measurement"
          data[:tags] = Array(data[:tags]).map(&:to_sym) | [:MEASUREMENT_ONLY]
          data
        end
      end
    end
  end
end
