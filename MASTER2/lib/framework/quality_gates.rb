# frozen_string_literal: true

require "yaml"

module MASTER
  module Framework
    # QualityGates - Configurable quality checks for code and tests
    class QualityGates
      @config = nil
      @config_mtime = nil

      class << self
        def config
          load_config unless @config
          @config
        end

        def load_config
          path = config_path
          return @config = default_config unless File.exist?(path)

          current_mtime = File.mtime(path)
          return @config if @config && @config_mtime == current_mtime

          @config = YAML.safe_load_file(path, symbolize_names: true)
          @config_mtime = current_mtime
          @config
        rescue StandardError => e
          warn "Failed to load quality gates config: #{e.message}"
          @config = default_config
        end

        def gates
          config[:gates] || []
        end

        def get_gate(name)
          gates.find { |g| g[:name] == name.to_sym }
        end

        def check_gate(name, metrics = {})
          gate = get_gate(name)
          return Result.err("Gate not found: #{name}") unless gate
          return Result.err("Gate disabled: #{name}") unless gate[:enabled]

          results = []
          passed = true

          gate[:checks].each do |check|
            result = evaluate_check(check, metrics)
            results << result
            passed = false unless result[:passed]
          end

          Result.ok(
            gate: name,
            passed: passed,
            checks: results,
            enforcement: gate[:enforcement],
            summary: summarize_results(results)
          )
        end

        def check_all(metrics = {})
          results = {}
          passed = true

          enabled_gates.each do |gate|
            gate_metrics = metrics[gate[:name]] || {}
            result = check_gate(gate[:name], gate_metrics)
            if result.ok?
              results[gate[:name]] = result.value
              passed = false unless result.value[:passed]
            end
          end

          Result.ok(
            passed: passed,
            gates: results,
            summary: summarize_all_gates(results)
          )
        end

        def check_syntax(files)
          metrics = { syntax_errors: 0 }

          files.each do |file|
            next unless File.exist?(file)
            begin
              RubyVM::InstructionSequence.compile_file(file) if file.end_with?(".rb")
            rescue SyntaxError
              metrics[:syntax_errors] += 1
            end
          end

          check_gate(:syntax, metrics)
        end

        def check_tests(test_results)
          metrics = {
            tests_passed: test_results[:passed] || 0,
            tests_failed: test_results[:failed] || 0,
            tests_skipped: test_results[:skipped] || 0,
            pass_rate: calculate_pass_rate(test_results),
          }

          check_gate(:tests, metrics)
        end

        def check_complexity(complexity_data)
          metrics = {
            cyclomatic_complexity: complexity_data[:cyclomatic] || 0,
            cognitive_complexity: complexity_data[:cognitive] || 0,
            max_method_lines: complexity_data[:max_method_lines] || 0,
          }

          check_gate(:complexity, metrics)
        end

        def check_coverage(coverage_data)
          metrics = {
            line_coverage: coverage_data[:line_coverage] || 0,
            branch_coverage: coverage_data[:branch_coverage] || 0,
          }

          check_gate(:coverage, metrics)
        end

        def enabled_gates
          gates.select { |g| g[:enabled] }
        end

        def gate_names
          gates.map { |g| g[:name] }
        end

        def clear_cache
          @config = nil
          @config_mtime = nil
        end

        private

        def config_path
          File.join(MASTER.root, "data", "quality_gates.yml")
        end

        def default_config
          {
            gates: [
              {
                name: :syntax,
                description: "No syntax errors",
                enabled: true,
                enforcement: :block,
                checks: [
                  { name: "No syntax errors", type: :exact, metric: :syntax_errors, threshold: 0, severity: :error }
                ],
              },
              {
                name: :tests,
                description: "Test requirements",
                enabled: true,
                enforcement: :block,
                checks: [
                  { name: "No failing tests", type: :exact, metric: :tests_failed, threshold: 0, severity: :error },
                  { name: "Minimum pass rate", type: :minimum, metric: :pass_rate, threshold: 95.0, severity: :warning },
                ],
              },
              {
                name: :complexity,
                description: "Complexity limits",
                enabled: true,
                enforcement: :warn,
                checks: [
                  { name: "Max cyclomatic", type: :maximum, metric: :cyclomatic_complexity, threshold: 15, severity: :warning },
                  { name: "Max method lines", type: :maximum, metric: :max_method_lines, threshold: 50, severity: :warning },
                ],
              },
              {
                name: :coverage,
                description: "Coverage requirements",
                enabled: false,
                enforcement: :warn,
                checks: [
                  { name: "Min line coverage", type: :minimum, metric: :line_coverage, threshold: 80.0, severity: :warning },
                ],
              },
            ],
          }
        end

        def evaluate_check(check, metrics)
          metric_key = check[:metric]
          metric_value = metrics[metric_key]
          threshold = check[:threshold]

          result = {
            check: check[:name],
            type: check[:type],
            threshold: threshold,
            actual: metric_value,
            passed: false,
            severity: check[:severity] || :warning,
          }

          return result.merge(error: "Metric #{metric_key} not provided") if metric_value.nil?

          case check[:type]
          when :minimum
            result[:passed] = metric_value >= threshold
          when :maximum
            result[:passed] = metric_value <= threshold
          when :exact
            result[:passed] = metric_value == threshold
          when :range
            min, max = threshold
            result[:passed] = metric_value >= min && metric_value <= max
          end

          result
        end

        def calculate_pass_rate(test_data)
          total = test_data[:passed].to_i + test_data[:failed].to_i
          return 0.0 if total.zero?
          (test_data[:passed].to_f / total * 100).round(2)
        end

        def summarize_results(results)
          passed = results.count { |r| r[:passed] }
          "#{passed}/#{results.size} checks passed"
        end

        def summarize_all_gates(results)
          passed = results.count { |_, r| r[:passed] }
          "#{passed}/#{results.size} gates passed"
        end
      end
    end
  end
end
