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

        def call(laws: nil)
          summary = Summary.new(checks: build_checks(laws:))
          @bus&.publish("self_test:complete", violations: summary.violation_count, checks: summary.to_h)
          @bus&.publish("self_violation", violations: summary.violation_count, checks: summary.to_h) unless summary.ok?
          Result.ok(summary)
        rescue StandardError => e
          @bus&.publish("self_test:error", error: e.message)
          Result.err("self-test failed: #{e.message}", category: :infrastructure)
        end

        private

        def build_checks(laws: nil)
          checks = [
            check("ROBUSTNESS") { bare_rescue_findings + deploy_bare_rescue_findings },
            check("SINGULARITY") { duplicate_rule_id_findings + deploy_duplicate_id_findings },
            check("LINEARITY") { structural_findings(Rules::NestingDepthRule.new) + deploy_nesting_findings },
            check("PROXIMITY") { rule_test_proximity_findings },
            check("ABSTRACTION") { structural_findings(Rules::GodClassRule.new) + deploy_god_class_findings },
            check("DENSITY") { structural_findings(Rules::SmallFunctionsRule.new) + deploy_small_files_findings },
          ]
          laws.nil? ? checks : checks.select { |item| laws.include?(item.law) }
        end

        # DEPLOY extensions for full self-application (rules.yml self_test + success_criteria)
        def deploy_bare_rescue_findings
          deploy_paths.flat_map do |path|
            next [] unless path.end_with?('.rb', '.sh')
            File.readlines(path, chomp: true).each_with_index.filter_map do |line, index|
              next unless line.match?(/^\s*rescue\s*(?:$|=>)/) || line.match?(/^\s*trap\s+.*\s+do/)
              finding(path:, line: index + 1, message: "bare rescue/trap in DEPLOY — use explicit error handling")
            end
          end
        end

        def deploy_duplicate_id_findings
          deploy_paths.select { |p| p.end_with?(".yml") }.flat_map do |path|
            yaml = Master.load_yaml(path)
            ids = rule_ids(yaml)
            ids.group_by(&:itself).filter_map do |id, values|
              finding(path:, line: 1, message: "duplicate id #{id} in DEPLOY config") if values.size > 1
            end
          rescue StandardError
            []
          end
        end

        def deploy_nesting_findings
          # Lightweight for sh/erb
          deploy_paths.flat_map do |path|
            next [] unless path.end_with?('.sh', '.erb')
            # Simple depth check for if/do/case nesting (extend with proper parser later)
            lines = File.readlines(path, chomp: true)
            depth = 0
            max = 0
            findings = []
            lines.each_with_index do |line, i|
              depth += 1 if line.match?(/^\s*(if|do|case|while|for)\b/)
              depth -= 1 if line.match?(/^\s*(fi|done|esac|end)\b/)
              max = [max, depth].max
              if depth > 4
                findings << finding(path:, line: i+1, message: "nesting >4 in DEPLOY (violates LINEARITY)")
              end
            end
            findings
          end
        end

        def deploy_god_class_findings
          # For Ruby in rails/
          deploy_paths.select { |p| p.end_with?('.rb') }.flat_map do |path|
            code = File.read(path, encoding: "UTF-8") rescue ""
            # Reuse GodClassRule logic if possible, else simple
            if code.scan(/^\s*def\s+\w+/).size > 10
              [finding(path:, line: 1, message: "potential god class in DEPLOY rails ( >10 defs )")]
            else
              []
            end
          end
        end

        def deploy_small_files_findings
          deploy_paths.select { |p| File.size(p) > 300 * 80 rescue false }.map do |path|  # rough >300 lines
            finding(path:, line: 1, message: "DEPLOY file >~300 lines (violates DENSITY/SMALL_FILES)")
          end
        end

        def check(law)
          Check.new(law:, description: @checks[law].to_s, findings: yield)
        end

        def ruby_lib_paths
          Dir.glob(File.join(@root, "lib", "**", "*.rb")).sort
        end

        def deploy_paths
          @deploy_paths ||= build_deploy_paths
        end

        def build_deploy_paths
          deploy_root = File.expand_path("../DEPLOY", @root)
          return [] unless File.directory?(deploy_root)

          patterns = [
            File.join(deploy_root, "rails", "**", "*.rb"),
            File.join(deploy_root, "openbsd", "**", "*"),
            File.join(deploy_root, "sh", "**", "*"),
            File.join(deploy_root, "postpro", "**", "*.rb"),
            File.join(deploy_root, "*.rb"),
          ]
          patterns.flat_map { |pattern| Dir.glob(pattern) }
                  .select { |path| File.file?(path) }
                  .select { |path| deploy_path_allowed?(path, deploy_root) }
                  .uniq.sort
        end

        def deploy_path_allowed?(path, deploy_root)
          rel = path.delete_prefix("#{deploy_root}/")
          !Scanner.skip_path?(rel) && !rel.split("/").include?("db")
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
          path = File.join(@root, "data", "rules.yml")
          ids = rule_ids(Master.load_yaml(path))
          ids.group_by(&:itself).filter_map do |id, values|
            finding(path:, line: 1, message: "duplicate rule id #{id}") if values.size > 1
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
