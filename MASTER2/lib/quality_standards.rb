# frozen_string_literal: true

require "yaml"

module MASTER
  # QualityStandards - Single source of truth for quality thresholds.
  # Implements ONE_SOURCE axiom: every threshold is defined exactly once.
  # All enforcement modules (validator, violations, enforcement, smells,
  # audit, code_review, introspection) MUST use these methods instead
  # of hardcoding their own thresholds.
  module QualityStandards
    THRESHOLDS_FILE = File.join(__dir__, "..", "data", "quality_thresholds.yml")

    class << self
      def thresholds
        @thresholds ||= load_thresholds
      end

      def reload!
        @thresholds = nil
        thresholds
      end

      # File thresholds
      def max_file_lines     = thresholds.dig("file", "max_lines") || 300
      def warn_file_lines    = thresholds.dig("file", "warn_lines") || 250
      def error_file_lines   = thresholds.dig("file", "error_lines") || 500

      # Method thresholds
      def max_method_lines   = thresholds.dig("method", "max_lines") || 25
      def max_method_params  = thresholds.dig("method", "max_params") || 4

      # Class thresholds
      def max_class_lines    = thresholds.dig("class", "max_lines") || 300

      # Naming thresholds
      def min_name_length    = thresholds.dig("naming", "min_length") || 3
      def max_name_length    = thresholds.dig("naming", "max_length") || 40

      # Self-test thresholds (same standards - no exceptions)
      def max_self_test_issues              = thresholds.dig("self_test", "max_issues") || 0
      def max_enforcement_violations        = thresholds.dig("self_test", "max_enforcement_violations") || 0

      # Convenience predicates
      def file_too_long?(line_count)
        line_count > max_file_lines
      end

      def file_warning?(line_count)
        line_count > warn_file_lines && line_count <= error_file_lines
      end

      def file_error?(line_count)
        line_count > error_file_lines
      end

      def method_too_long?(line_count)
        line_count > max_method_lines
      end

      private

      def load_thresholds
        return {} unless File.exist?(THRESHOLDS_FILE)
        YAML.safe_load_file(THRESHOLDS_FILE) || {}
      rescue StandardError => e
        $stderr.puts "QualityStandards: failed to load thresholds: #{e.message}" if ENV["MASTER_DEBUG"]
        {}
      end
    end
  end
end
