# frozen_string_literal: true

module Master
  module Fix
    # Blocks a clean/"done" outcome when an error finding violates any
    # constitutional invariant. All nine nodes are governing law; none is
    # silently dropped by a numeric cutoff.
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
        ids = constitutional_law_ids
        ids.nil? || ids.include?(law_id)
      end

      def residual_errors(findings)
        Array(findings).select { |f| constitutional_error?(f) }
      end

      def admit_clean?(findings)
        residual_errors(findings).empty?
      end

      def constitutional_law_ids
        return @constitutional_law_ids if @constitutional_law_ids_loaded

        @constitutional_law_ids = begin
          entries = Master.law_entries(root: Master::ROOT)
          ids = entries.filter_map do |entry|
            entry["id"].to_s if entry["node"]
          end
          raise "constitutional law catalogue has no ordered invariant nodes" unless ids.size == 9

          ids.freeze
        rescue StandardError => e
          warn("law0: constitutional catalogue unavailable; clean completion blocked (#{e.class})")
          nil
        end
        @constitutional_law_ids_loaded = true
        @constitutional_law_ids
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
