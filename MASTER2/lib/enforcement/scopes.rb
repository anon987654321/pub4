# frozen_string_literal: true

module MASTER
  module Enforcement
    # Three enforcement scopes: Lines, Units, Framework
    module Scopes
      # Scope 1: Line-by-line analysis
      def check_lines(code, filename)
        violations = []
        code.each_line.with_index(1) do |line, num|
          # TODO/FIXME/HACK markers
          if line.match?(/\b(TODO|FIXME|XXX|HACK)\b/)
            violations << { scope: :line, line: num, message: "Marker found: #{line.strip}", file: filename }
          end

          # Trailing whitespace
          if line.match?(/\s+$/)
            violations << { scope: :line, line: num, message: "Trailing whitespace", file: filename }
          end

          # Line length
          if line.chomp.length > (thresholds["line_length"] || 120)
            violations << { scope: :line, line: num, message: "Line too long (#{line.chomp.length} chars)", file: filename }
          end

          # Bare rescue
          if line.match?(/rescue\s*$/)
            violations << { scope: :line, line: num, message: "Bare rescue catches all errors", file: filename }
          end
        end

        violations
      end

      # Scope 2: Unit analysis (methods, classes)
      def check_units(code, filename)
        violations = []

        # Method length
        in_method = false
        method_start = 0
        method_name = nil
        code.each_line.with_index(1) do |line, num|
          if line.match?(/^\s*def\s+(\w+)/)
            in_method = true
            method_start = num
            method_name = line[/def\s+(\w+)/, 1]
          elsif in_method && line.match?(/^\s*end\s*$/)
            method_length = num - method_start
            limit = thresholds["method_length"] || 50
            if method_length > limit
              violations << { scope: :unit, message: "Method '#{method_name}' is #{method_length} lines (limit: #{limit})", file: filename }
            end
            in_method = false
          end
        end

        # Method parameter count
        code.scan(/def\s+(\w+)\s*\((.*?)\)/m).each do |method, params|
          param_count = params.split(",").size
          limit = thresholds["param_count"] || 5
          if param_count > limit
            violations << { scope: :unit, message: "Method '#{method}' has #{param_count} parameters (limit: #{limit})", file: filename }
          end
        end

        # Generic verbs
        generic_verbs = smells["generic_verbs"] || {}
        generic_verbs.keys.each do |verb|
          matches = code.scan(/def\s+(#{verb}_\w+)/)
          matches.each do |method_match|
            method = method_match.first
            better = generic_verbs[verb]&.first
            msg = better ? "Generic verb '#{verb}' in '#{method}' - try '#{better}'" : "Generic verb '#{verb}' in '#{method}'"
            violations << { scope: :unit, message: msg, file: filename }
          end
        end

        # Class method count
        class_methods = code.scan(/^\s*def\s+self\.(\w+)/).size
        if class_methods > (thresholds["class_methods"] || 15)
          violations << { scope: :unit, message: "Too many class methods (#{class_methods})", file: filename }
        end

        violations
      end

      # Scope 4: Framework-level (cross-file DRY violations)
      def check_framework(files, axioms)
        violations = []

        # DRY: duplicate constants across files
        constants = {}
        files.each do |filename, code|
          code.scan(/^\s*([A-Z][A-Z_]+)\s*=\s*(.+)$/).each do |name, value|
            constants[name] ||= []
            constants[name] << { file: filename, value: value }
          end
        end

        constants.each do |name, occurrences|
          next if occurrences.size <= 1
          unique_values = occurrences.map { |o| o[:value] }.uniq
          if unique_values.size == 1
            files_list = occurrences.map { |o| o[:file] }.join(", ")
            violations << { scope: :framework, axiom: "DRY", message: "Duplicate constant '#{name}' in: #{files_list}" }
          end
        end

        # Check for duplicate class names
        class_names = {}
        files.each do |filename, code|
          code.scan(/^\s*class\s+(\w+)/).flatten.each do |name|
            class_names[name] ||= []
            class_names[name] << filename
          end
        end

        class_names.each do |name, file_list|
          if file_list.size > 1
            violations << { scope: :framework, axiom: "ONE_SOURCE", message: "Duplicate class '#{name}' in: #{file_list.join(', ')}" }
          end
        end

        violations
      end
    end
  end
end
