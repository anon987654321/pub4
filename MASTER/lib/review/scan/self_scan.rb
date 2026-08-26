# frozen_string_literal: true

require_relative "mechanical_autofix"

module Master
  module Review
    module Scan
      class SelfScan
        DEFAULT_TARGETS = ["lib"].freeze

        Summary = Data.define(:pairs, :rule_count, :violation_count, :targets, :autofixes) do
          def line
            scanned = targets.map { |target| target.end_with?("/") ? target : "#{target}/" }.join("+")
            "judge: #{scanned} #{rule_count} rules, #{violation_count} violations"
          end
        end

        def initialize(scanner:, root:, event_bus: nil, targets: DEFAULT_TARGETS)
          @scanner = scanner
          @root = root
          @bus = event_bus
          @targets = targets
        end

        def call(stream: false, autofix: false)
          pairs = @targets.flat_map { |target| scan_target(target, stream:) }
          autofixes = autofix ? apply_autofixes(pairs) : []
          pairs = @targets.flat_map { |target| scan_target(target, stream:) } if autofixes.any?
          pairs.concat(singularity_pairs)
          summary = Summary.new(
            pairs:,
            rule_count:,
            violation_count: count_violations(pairs),
            targets: @targets,
            autofixes:,
          )
          publish(summary)
          Result.ok(summary)
        rescue StandardError => e
          @bus&.publish("self_scan:error", error: e.message)
          Result.err("self-scan failed: #{e.message}", category: :infrastructure)
        end

        private

        def scan_target(target, stream:)
          path = File.join(@root, target)
          result = @scanner.scan_dir(path, depth: :deep, stream:)
          Result.wrap(result).ok? ? result.value! : []
        end

        def singularity_pairs
          return [] unless File.exist?(File.join(@root, "data", "rules.yml"))

          result = SelfTest.new(root: @root, event_bus: @bus).call(laws: %w[SINGULARITY])
          return [] unless result.ok?

          check = result.value!.checks.find { |item| item.law == "SINGULARITY" }
          return [] unless check&.findings&.any?

          findings = check.findings.map do |finding|
            Finding.build(rule: "SINGULARITY", message: finding[:message], line: finding[:line],
              severity: :error, tags: %i[SINGULARITY])
          end
          [[File.join(@root, "data"), Result.ok(findings)]]
        end

        def rule_count
          return @scanner.rules.size if @scanner.respond_to?(:rules)

          Array(@scanner.instance_variable_get(:@rules)).size
        end

        def count_violations(pairs)
          pairs.sum { |_, file_result| Result.wrap(file_result).value_or([]).size }
        end

        def apply_autofixes(pairs)
          MechanicalAutofix.new(scanner: @scanner, root: @root, event_bus: @bus).apply(pairs).map do |applied|
            { path: applied.path, transforms: applied.transforms }
          end
        end

        def publish(summary)
          @bus&.publish("self_scan:complete", rules: summary.rule_count,
            violations: summary.violation_count, autofixes: summary.autofixes)
          return if summary.violation_count.zero?

          @bus&.publish("self_violation", rules: summary.rule_count, violations: summary.violation_count)
        end
      end
    end
  end
end
