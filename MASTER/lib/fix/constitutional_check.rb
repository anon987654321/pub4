# frozen_string_literal: true

module Master
  module Fix
    # Blocks a clean/"done" outcome when constitutional error-tier findings are
    # still present. Clean emptiness of a filtered list must not hide
    # priority≤3 errors that the pass observed earlier in the same run state.
    #
    # PassRunner calls admit_clean? before promoting consecutive_clean toward done.
    module ConstitutionalCheck
      module_function

      ERROR_SEVERITIES = %i[error veto critical fatal].freeze

      def constitutional_error?(finding)
        row = finding.respond_to?(:to_h) ? finding.to_h : finding
        row = row.transform_keys(&:to_sym) if row.is_a?(Hash)

        severity = row[:severity] || row["severity"]
        severity = severity.to_sym if severity.respond_to?(:to_sym)
        return false unless ERROR_SEVERITIES.include?(severity)

        tier = row[:tier] || row["tier"]
        return true if tier.to_s == "constitutional"

        law_id = (row[:law_id] || row["law_id"] || row[:id] || row["id"]).to_s
        priority_constitutional_ids.include?(law_id)
      end

      def residual_errors(findings)
        Array(findings).select { |f| constitutional_error?(f) }
      end

      def admit_clean?(findings)
        residual_errors(findings).empty?
      end

      def priority_constitutional_ids
        @priority_constitutional_ids ||= begin
          path = File.join(Master::ROOT, "data", "laws.yml")
          data = YAML.safe_load_file(path, aliases: true)
          data.select do |_id, spec|
            spec.is_a?(Hash) &&
              spec["tier"].to_s == "constitutional" &&
              spec.key?("priority") &&
              Integer(spec["priority"]) <= 3
          end.keys.map(&:to_s)
        rescue StandardError
          %w[CAPABILITY_STATUS_MUST_BE_TRUTHFUL ROBUSTNESS SINGULARITY LINEARITY]
        end
      end
    end
  end
end
