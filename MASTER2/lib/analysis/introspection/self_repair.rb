# frozen_string_literal: true

module Analysis
  module Introspection
    class SelfRepair
      def initialize(relation:, logger: nil)
        @relation = relation
        @logger = logger
      end

      def repair
        return [] unless repairable_relation?

        repair_findings = []
        load_repairable_findings.find_each do |finding|
          repair_findings.concat(repair_finding(finding))
        end
        repair_findings
      end

      private

      attr_reader :relation, :logger

      def repairable_relation?
        relation.respond_to?(:find_each)
      end

      def load_repairable_findings
        base = relation
        base = base.includes(:introspection_source) if supports_includes?(base)
        base
      end

      def supports_includes?(active_record_relation)
        active_record_relation.respond_to?(:includes)
      end

      def repair_finding(finding)
        return [] unless finding_needs_repair?(finding)

        applied_repairs = []
        applied_repairs << fix_missing_introspection_source(finding) if missing_introspection_source?(finding)
        applied_repairs << normalize_introspection_payload(finding) if payload_needs_normalization?(finding)
        applied_repairs.compact
      end

      def finding_needs_repair?(finding)
        missing_introspection_source?(finding) || payload_needs_normalization?(finding)
      end

      def missing_introspection_source?(finding)
        finding.respond_to?(:introspection_source) && finding.introspection_source.nil?
      end

      def fix_missing_introspection_source(finding)
        return unless finding.respond_to?(:build_introspection_source)
        return unless finding.respond_to?(:save!)

        finding.build_introspection_source
        finding.save!
        log_repair(finding, :created_introspection_source)
        :created_introspection_source
      rescue StandardError => e
        log_error(finding, e)
        nil
      end

      def payload_needs_normalization?(finding)
        finding.respond_to?(:payload) && finding.payload.is_a?(String)
      end

      def normalize_introspection_payload(finding)
        return unless finding.respond_to?(:payload=)
        return unless finding.respond_to?(:save!)

        finding.payload = finding.payload.strip
        finding.save!
        log_repair(finding, :normalized_payload)
        :normalized_payload
      rescue StandardError => e
        log_error(finding, e)
        nil
      end

      def log_repair(finding, action)
        return unless logger

        logger.info("[SelfRepair] #{action} for #{finding.class}(id=#{safe_id(finding)})")
      end

      def log_error(finding, error)
        return unless logger

        logger.warn(
          "[SelfRepair] failed for #{finding.class}(id=#{safe_id(finding)}): #{error.class} - #{error.message}"
        )
      end

      def safe_id(record)
        record.respond_to?(:id) ? record.id : "unknown"
      end
    end
  end
end