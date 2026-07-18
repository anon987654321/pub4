# frozen_string_literal: true

module Master
  module Fix
    # Applies MASTER's canonical scanner to its own lib/ tree.
    class SelfCheck
      QUICK_SEVERITIES = %i[error critical].freeze

      Report = Data.define(:total, :by_rule, :by_severity, :error) do
        def clean? = total.zero? && error.nil?
        def summary
          return "selfcheck: failed — #{error}" if error
          return "selfcheck: clean" if clean?

          "selfcheck: #{total} violation(s) across #{by_rule.size} rule(s)"
        end
      end

      def initialize(root: Master::ROOT, scanner: nil)
        @root = File.expand_path(root)
        @scanner = scanner || Master::Review::Scan::InfraHelpers.build_scanner(root: @root)
      end

      def quick = run(severity_filter: QUICK_SEVERITIES)
      def full = run(severity_filter: nil)

      private

      def run(severity_filter:)
        result = @scanner.scan_dir(File.join(@root, "lib"), depth: :deep, stream: false)
        return failed_report(result.message) if result.respond_to?(:err?) && result.err?

        violations = flatten_violations(result.value!)
        violations = filter_severities(violations, severity_filter)
        build_report(violations)
      rescue StandardError => e
        failed_report("#{e.class}: #{e.message}")
      end

      def build_report(violations)
        by_rule = violations.group_by { |item| item[:rule] }.transform_values(&:size)
        by_severity = violations.group_by { |item| item[:severity] }.transform_values(&:size)
        Report.new(total: violations.size, by_rule:, by_severity:, error: nil)
      end

      def flatten_violations(results)
        results.flat_map do |_path, scan_result|
          scan_result.respond_to?(:ok?) && scan_result.ok? ? scan_result.value! : []
        end
      end

      def filter_severities(violations, filter)
        return violations unless filter

        violations.select { |item| filter.include?(item[:severity].to_s.to_sym) }
      end

      def failed_report(message)
        Report.new(total: 0, by_rule: {}, by_severity: {}, error: message)
      end
    end
  end
end
