# frozen_string_literal: true

require 'yaml'

module MASTER
  module Framework
    class UniversalStandards
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
          warn "Failed to load universal standards config: #{e.message}"
          @config = default_config
        end

        def standards
          config[:standards] || []
        end

        def get_standard(name)
          standards.find { |s| s[:name] == name.to_sym }
        end

        def validate_code(code, language = :ruby)
          violations = []
          applicable = standards.select { |s| s[:enabled] && applies_to?(s, language) }

          applicable.each do |standard|
            result = check_standard(standard, code, language)
            violations.concat(result) if result.any?
          end

          {
            valid: violations.empty?,
            violations: violations,
            standards_checked: applicable.size,
            summary: summarize_violations(violations)
          }
        end

        def check_standard(standard, code, language)
          violations = []
          rules = standard[:rules] || []

          rules.each do |rule|
            next unless rule[:enabled]
            
            if rule[:type] == 'line_length'
              violations.concat(check_line_length(code, rule))
            elsif rule[:type] == 'indentation'
              violations.concat(check_indentation(code, rule, language))
            elsif rule[:type] == 'naming'
              violations.concat(check_naming(code, rule, language))
            elsif rule[:type] == 'complexity'
              violations.concat(check_complexity(code, rule))
            elsif rule[:type] == 'documentation'
              violations.concat(check_documentation(code, rule, language))
            end
          end

          violations
        end

        def check_line_length(code, rule)
          violations = []
          max_length = rule[:max_length] || 120

          code.lines.each_with_index do |line, idx|
            if line.chomp.length > max_length
              violations << {
                line: idx + 1,
                standard: :line_length,
                severity: rule[:severity] || :warning,
                message: "Line exceeds #{max_length} characters (#{line.chomp.length})",
                type: :formatting
              }
            end
          end

          violations
        end

        def check_indentation(code, rule, language)
          violations = []
          indent_size = rule[:indent_size] || 2
          use_spaces = rule[:use_spaces].nil? ? true : rule[:use_spaces]

          code.lines.each_with_index do |line, idx|
            next if line.strip.empty?

            match = line.match(/^(\s+)/)
            leading = match ? match[1] : ''
            
            if use_spaces && leading.include?("\t")
              violations << {
                line: idx + 1,
                standard: :indentation,
                severity: rule[:severity] || :warning,
                message: 'Mixed tabs and spaces in indentation',
                type: :formatting
              }
            elsif !use_spaces && leading.include?(' ')
              violations << {
                line: idx + 1,
                standard: :indentation,
                severity: rule[:severity] || :warning,
                message: 'Spaces used instead of tabs',
                type: :formatting
              }
            elsif use_spaces && leading.length % indent_size != 0
              violations << {
                line: idx + 1,
                standard: :indentation,
                severity: rule[:severity] || :info,
                message: "Indentation not multiple of #{indent_size}",
                type: :formatting
              }
            end
          end

          violations
        end

        def check_naming(code, rule, language)
          return [] unless language == :ruby
          
          violations = []
          violations.concat(check_class_naming(code, rule))
          violations.concat(check_method_naming(code, rule))
          violations
        end

        def check_class_naming(code, rule)
          code.scan(/^\s*class\s+([a-z]\w*)/i).filter_map do |match|
            name = match[0]
            next if name.match?(/^[A-Z][a-z0-9]*([A-Z][a-z0-9]*)*$/)
            { standard: :naming, severity: rule[:severity] || :warning, message: "Class name '#{name}' should be PascalCase", type: :naming }
          end
        end

        def check_method_naming(code, rule)
          code.scan(/^\s*def\s+([A-Z]\w*)/i).filter_map do |match|
            name = match[0]
            next unless name.match?(/[A-Z]/)
            { standard: :naming, severity: rule[:severity] || :warning, message: "Method name '#{name}' should be snake_case", type: :naming }
          end
        end

        def check_complexity(code, rule)
          violations = []
          max_complexity = rule[:max_complexity] || 10

          # Simple cyclomatic complexity approximation
          methods = extract_methods(code)
          methods.each do |method|
            complexity = calculate_complexity(method[:body])
            if complexity > max_complexity
              violations << {
                line: method[:line],
                standard: :complexity,
                severity: rule[:severity] || :warning,
                message: "Method '#{method[:name]}' has complexity #{complexity} (max: #{max_complexity})",
                type: :complexity
              }
            end
          end

          violations
        end

        def check_documentation(code, rule, language)
          violations = []
          
          if language == :ruby
            # Check for class documentation
            code.scan(/^\s*class\s+(\w+)/i).each do |match|
              class_name = match[0]
              unless has_documentation_before?(code, "class #{class_name}")
                violations << {
                  standard: :documentation,
                  severity: rule[:severity] || :info,
                  message: "Class '#{class_name}' missing documentation",
                  type: :documentation
                }
              end
            end
          end

          violations
        end

        def enforce_standard(name)
          standard = get_standard(name)
          return { success: false, error: 'Standard not found' } unless standard
          return { success: false, error: 'Standard disabled' } unless standard[:enabled]

          {
            success: true,
            standard: standard,
            enforcement: standard[:enforcement] || 'warn'
          }
        end

        def format_code(code, language = :ruby, options = {})
          formatted = code.dup
          
          if options[:fix_indentation]
            formatted = fix_indentation(formatted, language)
          end
          
          if options[:fix_line_length]
            formatted = fix_line_length(formatted)
          end

          {
            code: formatted,
            changes: code != formatted
          }
        end

        def clear_cache
          @config = nil
          @config_mtime = nil
        end

        def enabled_standards
          standards.select { |s| s[:enabled] }
        end

        def standard_names
          standards.map { |s| s[:name] }
        end

        private

        def config_path
          File.join(Paths.config_root, 'framework', 'universal_standards.yml')
        end

        def default_config
          {
            standards: [
              {
                name: :coding_style,
                description: 'Coding style and formatting standards',
                enabled: true,
                languages: [:ruby, :python, :javascript],
                rules: []
              },
              {
                name: :documentation,
                description: 'Documentation requirements',
                enabled: true,
                languages: [:all],
                rules: []
              },
              {
                name: :complexity,
                description: 'Code complexity limits',
                enabled: true,
                languages: [:all],
                rules: []
              }
            ]
          }
        end

        def applies_to?(standard, language)
          langs = standard[:languages] || []
          langs.include?(:all) || langs.include?(language)
        end

        def extract_methods(code)
          methods = []
          current_method = nil
          depth = 0

          code.lines.each_with_index do |line, idx|
            if line.match?(/^\s*def\s+(\w+)/)
              name = line.match(/def\s+(\w+)/)[1]
              current_method = { name: name, line: idx + 1, body: '', depth: 0 }
              methods << current_method
            elsif current_method
              current_method[:body] += line
              depth += 1 if line.match?(/\b(if|unless|while|until|for|case)\b/)
              depth -= 1 if line.match?(/\bend\b/)
              current_method = nil if depth < 0
            end
          end

          methods
        end

        def calculate_complexity(code)
          # Simple cyclomatic complexity: 1 + number of decision points
          complexity = 1
          complexity += code.scan(/\b(if|unless|while|until|for|case|&&|\|\|)\b/).size
          complexity
        end

        def has_documentation_before?(code, target)
          lines = code.lines
          target_idx = lines.index { |l| l.include?(target) }
          return false unless target_idx && target_idx > 0

          # Check previous line for comment
          lines[target_idx - 1].match?(/^\s*#/)
        end

        def fix_indentation(code, language)
          # Placeholder for auto-fixing indentation
          code
        end

        def fix_line_length(code)
          # Placeholder for auto-fixing line length
          code
        end

        def summarize_violations(violations)
          return 'No violations' if violations.empty?

          by_type = violations.group_by { |v| v[:type] }
          by_type.map { |type, viols| "#{viols.size} #{type}" }.join(', ')
        end
      end
    end
  end
end
