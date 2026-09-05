# frozen_string_literal: true

module Master
  module Fix
    # Applies MASTER's canonical scanner to MASTER's own source, over the roots
    # data/scan_coverage.yml declares rather than a hardcoded lib/.
    class SelfCheck
      QUICK_SEVERITIES = %i[error critical].freeze

      Report = Data.define(:total, :by_rule, :by_severity, :error, :findings) do
        def clean? = total.zero? && error.nil?

        # The headline on its own, so a caller that has already printed the
        # located findings can fail with the count rather than repeating them.
        def line
          return "selfcheck: failed — #{error}" if error
          return "selfcheck: clean" if clean?

          "selfcheck: #{total} violation(s) across #{by_rule.size} rule(s)"
        end

        def summary
          return line if error || clean?

          lines = [line]
          Array(findings).first(20).each do |item|
            lines << "  #{item[:path]}:#{item[:line]} #{item[:rule]}"
          end
          extra = Array(findings).size - 20
          lines << "  … and #{extra} more" if extra.positive?
          lines.join("\n")
        end
      end

      def initialize(root: Master::ROOT, scanner: nil)
        @root = File.expand_path(root)
        @scanner = scanner || Master::Review::Scan::InfraHelpers.build_scanner(root: @root)
      end

      def quick = run(severity_filter: QUICK_SEVERITIES)
      def full = run(severity_filter: nil)

      # Hard gate for callers about to start background autofix or other
      # self-mutation: refuse (by returning a non-clean report) when MASTER's
      # own lib/ tree already carries violations, and publish self_violation
      # so any subscriber (e.g. FixLoop#halt!) reacts the same way it would
      # to a violation discovered mid-run.
      def gate!(bus: nil)
        report = quick
        return report if report.clean?

        bus&.publish("self_violation", violations: report.total, by_rule: report.by_rule)
        report
      end

      private

      def run(severity_filter:)
        violations = []
        scan_dirs.each do |dir|
          result = @scanner.scan_dir(dir, depth: :deep, stream: false)
          return failed_report(result.message) if result.respond_to?(:err?) && result.err?

          violations.concat(flatten_violations(result.value!))
        end
        build_report(filter_severities(violations, severity_filter))
      rescue StandardError => e
        failed_report("#{e.class}: #{e.message}")
      end

      # data/scan_coverage.yml, not File.join(@root, "lib") — see Master.scan_roots.
      def scan_dirs
        Master.scan_roots(root: @root)
              .map { |dir| File.join(@root, dir) }
              .select { |dir| Dir.exist?(dir) }
      end

      def build_report(violations)
        by_rule = violations.group_by { |item| item[:rule] }.transform_values(&:size)
        by_severity = violations.group_by { |item| item[:severity] }.transform_values(&:size)
        Report.new(total: violations.size, by_rule:, by_severity:, error: nil, findings: violations)
      end

      def flatten_violations(results)
        results.flat_map do |path, scan_result|
          rows = scan_result.respond_to?(:ok?) && scan_result.ok? ? scan_result.value! : []
          rows.map { |item| item.merge(path:) }
        end
      end

      def filter_severities(violations, filter)
        return violations unless filter

        violations.select { |item| filter.include?(item[:severity].to_s.to_sym) }
      end

      def failed_report(message)
        Report.new(total: 0, by_rule: {}, by_severity: {}, error: message, findings: [])
      end
    end
  end
end
