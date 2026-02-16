# frozen_string_literal: true

module MASTER
  module Review
    # QualityStandards - Unified quality thresholds from quality_thresholds.yml
    module QualityStandards
      extend self

      THRESHOLDS_FILE = File.join(MASTER.root, "data", "quality_thresholds.yml")

      def thresholds
        @thresholds ||= begin
          return defaults unless File.exist?(THRESHOLDS_FILE)
          YAML.safe_load_file(THRESHOLDS_FILE, symbolize_names: true) || defaults
        end
      end

      def defaults
        {
          file_lines: { warn: 500, error: 600, self_test_max: 600 },
          method_lines: { warn: 15, error: 25 },
          max_self_test_issues: 0,
          max_self_test_violations: 0
        }
      end

      def max_file_lines
        thresholds.dig(:file_lines, :error) || 600
      end

      def max_file_lines_warn
        thresholds.dig(:file_lines, :warn) || 250
      end

      def max_file_lines_self_test
        thresholds.dig(:file_lines, :self_test_max) || 600
      end

      def max_method_lines
        thresholds.dig(:method_lines, :error) || 25
      end

      def max_method_lines_warn
        thresholds.dig(:method_lines, :warn) || 15
      end

      def max_self_test_issues
        thresholds[:max_self_test_issues] || 0
      end

      def max_self_test_violations
        thresholds[:max_self_test_violations] || 0
      end
    end
  end
end
