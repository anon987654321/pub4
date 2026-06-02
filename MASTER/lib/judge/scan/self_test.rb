# frozen_string_literal: true

require_relative "rule_dsl"

module Master
  module Judge
    module Scan
      class SelfTest
        Check = Data.define(:law, :description, :findings) do
          def ok? = findings.empty?
        end

        Summary = Data.define(:checks) do
          def violation_count = checks.sum { |check| check.findings.size }
          def ok? = violation_count.zero?
          def line = "self-test: #{violation_count} violations"
          def to_h = checks.to_h { |check| [check.law, { ok: check.ok?, findings: check.findings }] }
        end

        def initialize(root:, event_bus: nil)
          @root = root
          @bus = event_bus
          @checks = Master.load_yaml(File.join(root, "data", "rules.yml"))
                          .dig("self_test", "laws_apply_to_self") || {}
        end

        def call
          summary = Summary.new(checks: build_checks)
          @bus&.publish("self_test:complete", violations: summary.violation_count, checks: summary.to_h)
          @bus&.publish("self_violation", violations: summary.violation_count, checks: summary.to_h) unless summary.ok?
          Result.ok(summary)
        rescue StandardError => e
          @bus&.publish("self_test:error", error: e.message)
          Result.err("self-test failed: #{e.message}", category: :infrastructure)
        end

        private

        def build_checks
          [
            check("ROBUSTNESS") { bare_rescue_findings },
            check("SINGULARITY") { duplicate_rule_id_findings },
            check("LINEARITY") { structural_findings(Rules::NestingDepthRule.new) },
            check("PROXIMITY") { rule_test_proximity_findings },
            check("ABSTRACTION") { structural_findings(Rules::GodClassRule.new) },
            check("DENSITY") { structural_findings(Rules::SmallFunctionsRule.new) }
          ]
        end

        def check(law)
          Check.new(law:, description: @checks[law].to_s, findings: yield)
        end

        def ruby_lib_paths
          Dir.glob(File.join(@root, "lib", "**", "*.rb")).sort
        end

        def bare_rescue_findings
          ruby_lib_paths.flat_map do |path|
            File.readlines(path, chomp: true).each_with_index.filter_map do |line, index|
              next unless line.match?(/^\s*rescue\s*(?:$|=>)/)

              finding(path:, line: index + 1, message: "bare rescue — use rescue StandardError")
            end
          end
        end

        def duplicate_rule_id_findings
          ids = rule_ids(Master.load_yaml(File.join(@root, "data", "rules.yml")))
          ids.group_by(&:itself).filter_map do |id, values|
            finding(path: File.join(@root, "data", "rules.yml"), line: 1, message: "duplicate rule id #{id}") if values.size > 1
          end
        end

        def rule_ids(value, ids = [])
          case value
          when Hash
            ids << value["id"].to_s if value.key?("id")
            value.each_value { |child| rule_ids(child, ids) }
          when Array
            value.each { |child| rule_ids(child, ids) }
          end
          ids.reject(&:empty?)
        end

        def structural_findings(rule)
          ruby_lib_paths.flat_map do |path|
            code = File.read(path, encoding: "UTF-8")
            rule.check(code, path:).map { |result| finding(path:, line: result.line, message: result.message) }
          end
        end

        def rule_test_proximity_findings
          Dir.glob(File.join(@root, "lib", "judge", "scan", "rules", "*_rule.rb")).sort.filter_map do |path|
            base = File.basename(path, ".rb")
            test_path = File.join(@root, "test", "test_#{base}.rb")
            next if File.exist?(test_path)

            finding(path:, line: 1, message: "missing nearby test #{File.basename(test_path)}")
          end
        end

        def finding(path:, line:, message:)
          { path:, line:, message: }
        end
      end
    end
  end
end
