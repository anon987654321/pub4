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
        ids = priority_constitutional_ids
        ids.nil? || ids.include?(law_id)
      end

      def residual_errors(findings)
        Array(findings).select { |f| constitutional_error?(f) }
      end

      def admit_clean?(findings)
        residual_errors(findings).empty?
      end

      def priority_constitutional_ids
        return @priority_constitutional_ids if @priority_constitutional_ids_loaded

        @priority_constitutional_ids = begin
          entries = Master.law_entries(root: Master::ROOT)
          ids = entries.filter_map do |entry|
            next unless entry["tier"].to_s == "constitutional"
            next unless entry.key?("priority") && Integer(entry["priority"]) <= 3

            entry["id"].to_s
          end
          raise "priority constitutional law catalogue is empty" if ids.empty?

          ids.freeze
        rescue StandardError => e
          warn("law0: priority constitutional catalogue unavailable; clean completion blocked (#{e.class})")
          nil
        end
        @priority_constitutional_ids_loaded = true
        @priority_constitutional_ids
      end
    end
  end
end
