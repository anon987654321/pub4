# frozen_string_literal: true

require 'yaml'

module MASTER
  module Framework
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
          if @config && @config_mtime == current_mtime
            return @config
          end

          @config = YAML.load_file(path, symbolize_names: true)
          @config_mtime = current_mtime
          @config
        rescue => e
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
          return { success: false, error: 'Gate not found' } unless gate
          return { success: false, error: 'Gate disabled' } unless gate[:enabled]

          results = []
          passed = true

          gate[:checks].each do |check|
            result = evaluate_check(check, metrics)
            results << result
            passed = false unless result[:passed]
          end

          {
            success: true,
            gate: name,
            passed: passed,
            checks: results,
            summary: summarize_results(results)
          }
        end

        def evaluate_check(check, metrics)
          check_type = check[:type]
          threshold = check[:threshold]
          metric_key = check[:metric]
          metric_value = metrics[metric_key]

          result = {
            check: check[:name],
            type: check_type,
            threshold: threshold,
            actual: metric_value,
            passed: false,
            severity: check[:severity] || :warning
          }

          if metric_value.nil?
            result[:error] = "Metric '#{metric_key}' not provided"
            return result
          end

          case check_type
          when :minimum
            result[:passed] = metric_value >= threshold
            result[:message] = "#{metric_key}: #{metric_value} (min: #{threshold})"
          when :maximum
            result[:passed] = metric_value <= threshold
            result[:message] = "#{metric_key}: #{metric_value} (max: #{threshold})"
          when :range
            min, max = threshold
            result[:passed] = metric_value >= min && metric_value <= max
            result[:message] = "#{metric_key}: #{metric_value} (range: #{min}-#{max})"
          when :exact
            result[:passed] = metric_value == threshold
            result[:message] = "#{metric_key}: #{metric_value} (expected: #{threshold})"
          when :boolean
            result[:passed] = metric_value == threshold
            result[:message] = "#{metric_key}: #{metric_value}"
          else
            result[:error] = "Unknown check type: #{check_type}"
          end

          result
        end

        def check_test_coverage(coverage_data)
          gate = get_gate(:test_coverage)
          return { success: false, error: 'Test coverage gate not found' } unless gate

          metrics = {
            line_coverage: coverage_data[:line_coverage],
            branch_coverage: coverage_data[:branch_coverage],
            total_coverage: coverage_data[:total_coverage]
          }

          check_gate(:test_coverage, metrics)
        end

        def check_code_complexity(complexity_data)
          gate = get_gate(:complexity)
          return { success: false, error: 'Complexity gate not found' } unless gate

          metrics = {
            cyclomatic_complexity: complexity_data[:cyclomatic],
            cognitive_complexity: complexity_data[:cognitive],
            max_method_complexity: complexity_data[:max_method]
          }

          check_gate(:complexity, metrics)
        end

        def check_security(security_data)
          gate = get_gate(:security)
          return { success: false, error: 'Security gate not found' } unless gate

          metrics = {
            critical_vulnerabilities: security_data[:critical] || 0,
            high_vulnerabilities: security_data[:high] || 0,
            medium_vulnerabilities: security_data[:medium] || 0,
            total_vulnerabilities: security_data[:total] || 0
          }

          check_gate(:security, metrics)
        end

        def check_test_results(test_data)
          gate = get_gate(:tests)
          return { success: false, error: 'Test gate not found' } unless gate

          metrics = {
            tests_passed: test_data[:passed] || 0,
            tests_failed: test_data[:failed] || 0,
            tests_skipped: test_data[:skipped] || 0,
            pass_rate: calculate_pass_rate(test_data)
          }

          check_gate(:tests, metrics)
        end

        def check_performance(performance_data)
          gate = get_gate(:performance)
          return { success: false, error: 'Performance gate not found' } unless gate

          metrics = {
            response_time: performance_data[:response_time],
            throughput: performance_data[:throughput],
            error_rate: performance_data[:error_rate]
          }

          check_gate(:performance, metrics)
        end

        def check_all_gates(all_metrics = {})
          results = {}
          passed = true

          enabled_gates.each do |gate|
            gate_metrics = all_metrics[gate[:name]] || {}
            result = check_gate(gate[:name], gate_metrics)
            results[gate[:name]] = result
            passed = false unless result[:passed]
          end

          {
            success: true,
            passed: passed,
            gates: results,
            summary: summarize_all_gates(results)
          }
        end

        def gate_status(name)
          gate = get_gate(name)
          return { success: false, error: 'Gate not found' } unless gate

          {
            success: true,
            name: gate[:name],
            enabled: gate[:enabled],
            enforcement: gate[:enforcement] || 'warn',
            checks: gate[:checks].size
          }
        end

        def clear_cache
          @config = nil
          @config_mtime = nil
        end

        def enabled_gates
          gates.select { |g| g[:enabled] }
        end

        def gate_names
          gates.map { |g| g[:name] }
        end

        private

        def config_path
          File.join(Paths.config_root, 'framework', 'quality_gates.yml')
        end

        def default_config
          {
            gates: [
              {
                name: :test_coverage,
                description: 'Code coverage requirements',
                enabled: true,
                enforcement: 'block',
                checks: [
                  {
                    name: 'Minimum line coverage',
                    type: :minimum,
                    metric: :line_coverage,
                    threshold: 80.0,
                    severity: :error
                  }
                ]
              },
              {
                name: :complexity,
                description: 'Code complexity limits',
                enabled: true,
                enforcement: 'warn',
                checks: [
                  {
                    name: 'Maximum cyclomatic complexity',
                    type: :maximum,
                    metric: :cyclomatic_complexity,
                    threshold: 10,
                    severity: :warning
                  }
                ]
              },
              {
                name: :security,
                description: 'Security vulnerability checks',
                enabled: true,
                enforcement: 'block',
                checks: [
                  {
                    name: 'No critical vulnerabilities',
                    type: :exact,
                    metric: :critical_vulnerabilities,
                    threshold: 0,
                    severity: :error
                  }
                ]
              },
              {
                name: :tests,
                description: 'Test execution requirements',
                enabled: true,
                enforcement: 'block',
                checks: [
                  {
                    name: 'No failing tests',
                    type: :exact,
                    metric: :tests_failed,
                    threshold: 0,
                    severity: :error
                  },
                  {
                    name: 'Minimum pass rate',
                    type: :minimum,
                    metric: :pass_rate,
                    threshold: 95.0,
                    severity: :warning
                  }
                ]
              },
              {
                name: :performance,
                description: 'Performance benchmarks',
                enabled: false,
                enforcement: 'warn',
                checks: []
              }
            ]
          }
        end

        def calculate_pass_rate(test_data)
          total = test_data[:passed].to_i + test_data[:failed].to_i
          return 0.0 if total.zero?
          
          (test_data[:passed].to_f / total * 100).round(2)
        end

        def summarize_results(results)
          passed = results.count { |r| r[:passed] }
          total = results.size
          
          "#{passed}/#{total} checks passed"
        end

        def summarize_all_gates(results)
          passed_gates = results.count { |_, r| r[:passed] }
          total_gates = results.size
          
          "#{passed_gates}/#{total_gates} gates passed"
        end
      end
    end
  end
end
