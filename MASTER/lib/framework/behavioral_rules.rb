# frozen_string_literal: true

require 'yaml'

module MASTER
  module Framework
    class BehavioralRules
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
          warn "Failed to load behavioral rules config: #{e.message}"
          @config = default_config
        end

        def rules
          config[:rules] || []
        end

        def get_rule(category)
          rules.find { |r| r[:category] == category.to_sym }
        end

        def validate_behavior(code, context = {})
          violations = []
          
          rules.each do |rule|
            next unless rule[:enabled]
            
            result = check_rule(rule, code, context)
            violations.concat(result) if result.any?
          end

          {
            valid: violations.empty?,
            violations: violations,
            summary: summarize_violations(violations)
          }
        end

        def check_rule(rule, code, context)
          violations = []
          patterns = rule[:patterns] || []

          patterns.each do |pattern|
            if pattern[:type] == 'regex'
              violations.concat(check_regex_pattern(pattern, code, rule))
            elsif pattern[:type] == 'semantic'
              violations.concat(check_semantic_pattern(pattern, code, context, rule))
            end
          end

          violations
        end

        def check_regex_pattern(pattern, code, rule)
          violations = []
          regex = Regexp.new(pattern[:pattern])

          code.lines.each_with_index do |line, idx|
            if line.match?(regex)
              violations << {
                line: idx + 1,
                rule: rule[:category],
                severity: rule[:severity] || :warning,
                message: pattern[:message] || rule[:description],
                type: :behavioral
              }
            end
          end

          violations
        end

        def check_semantic_pattern(pattern, code, context, rule)
          # Placeholder for LLM-based semantic checking
          # This would integrate with MASTER::LLM for deeper analysis
          []
        end

        def enforce_rule(category, options = {})
          rule = get_rule(category)
          return { success: false, error: 'Rule not found' } unless rule
          return { success: false, error: 'Rule disabled' } unless rule[:enabled]

          {
            success: true,
            rule: rule,
            enforcement: rule[:enforcement] || 'warn',
            auto_fix: rule[:auto_fix] || false
          }
        end

        def suggest_fix(violation)
          rule = get_rule(violation[:rule])
          return nil unless rule

          fixes = rule[:fixes] || []
          fixes.find { |f| f[:pattern] == violation[:pattern] }&.dig(:suggestion)
        end

        def apply_fixes(code, violations)
          fixed_code = code.dup
          applied_fixes = []

          violations.each do |violation|
            fix = suggest_fix(violation)
            next unless fix

            if apply_fix(fixed_code, violation, fix)
              applied_fixes << violation
            end
          end

          {
            code: fixed_code,
            applied: applied_fixes.size,
            remaining: violations.size - applied_fixes.size
          }
        end

        def apply_fix(code, violation, fix)
          # Simple line-based fix application
          return false unless violation[:line]

          lines = code.lines
          return false if violation[:line] > lines.size

          # Apply fix suggestion (placeholder - real implementation would be more sophisticated)
          true
        rescue
          false
        end

        def clear_cache
          @config = nil
          @config_mtime = nil
        end

        def categories
          rules.map { |r| r[:category] }
        end

        def enabled_rules
          rules.select { |r| r[:enabled] }
        end

        def disabled_rules
          rules.reject { |r| r[:enabled] }
        end

        def rule_statistics
          {
            total: rules.size,
            enabled: enabled_rules.size,
            disabled: disabled_rules.size,
            by_severity: rules.group_by { |r| r[:severity] }.transform_values(&:size)
          }
        end

        private

        def config_path
          File.join(Paths.config_root, 'framework', 'behavioral_rules.yml')
        end

        def default_config
          {
            rules: [
              {
                category: :autonomy,
                description: 'Agent autonomy and decision-making rules',
                severity: :warning,
                enabled: true,
                patterns: []
              },
              {
                category: :collaboration,
                description: 'Multi-agent collaboration patterns',
                severity: :info,
                enabled: true,
                patterns: []
              },
              {
                category: :safety,
                description: 'Safety and constraint rules',
                severity: :error,
                enabled: true,
                patterns: []
              }
            ]
          }
        end

        def summarize_violations(violations)
          return 'No violations' if violations.empty?

          by_severity = violations.group_by { |v| v[:severity] }
          parts = []
          parts << "#{by_severity[:error]&.size || 0} errors" if by_severity[:error]
          parts << "#{by_severity[:warning]&.size || 0} warnings" if by_severity[:warning]
          parts << "#{by_severity[:info]&.size || 0} info" if by_severity[:info]
          
          parts.join(', ')
        end
      end
    end
  end
end
