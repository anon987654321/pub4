# frozen_string_literal: true

module MASTER
  module Agents
    class StyleAgent < BaseAgent
      def analyze(code, file_path = nil)
        clear_findings
        
        # Check against loaded principles
        @principles.each do |principle|
          check_principle_violations(code, principle)
        end

        # Basic style checks
        check_naming_conventions(code)
        check_method_complexity(code)
        check_line_length(code)
        check_comments(code)

        @findings
      end

      private

      def check_principle_violations(code, principle)
        # Check for specific anti-patterns defined in principle
        principle.anti_patterns.each do |pattern_name, pattern_data|
          smell = pattern_data[:smell]
          next unless smell

          # Simple substring check - could be enhanced with regex
          if code.downcase.include?(smell.downcase)
            add_finding(
              severity: principle.priority > 7 ? :high : :medium,
              category: :style,
              message: "Potential violation of '#{principle.name}': #{smell}",
              suggestion: pattern_data[:fix]
            )
          end
        end
      end

      def check_naming_conventions(code)
        # Check for poor variable names
        code.scan(/(\w+)\s*=/) do |match|
          var_name = match[0]
          if var_name.length <= 2 && !%w[i j k x y z].include?(var_name)
            add_finding(
              severity: :low,
              category: :style,
              message: "Variable name '#{var_name}' is too short",
              suggestion: "Use descriptive names (Principle: Meaningful Names)"
            )
          end
        end

        # Check for magic numbers
        code.scan(/\b\d{3,}\b/) do |match|
          add_finding(
            severity: :low,
            category: :style,
            message: "Magic number '#{match}' detected",
            suggestion: "Extract to named constant"
          )
        end
      end

      def check_method_complexity(code)
        # Simple method complexity check
        code.scan(/def\s+(\w+).*?(?=\n\s*def\s|\n\s*end\s|\z)/m) do |match|
          method_body = $&
          lines = method_body.lines.count { |l| !l.strip.empty? && !l.strip.start_with?('#') }
          
          if lines > 25
            add_finding(
              severity: :high,
              category: :style,
              message: "Method '#{match[0]}' is too long (#{lines} lines)",
              suggestion: "Break down into smaller methods (Principle: Small Functions)"
            )
          end
        end
      end

      def check_line_length(code)
        code.lines.each_with_index do |line, idx|
          if line.length > 120
            add_finding(
              severity: :low,
              category: :style,
              message: "Line #{idx + 1} exceeds 120 characters",
              line: idx + 1,
              suggestion: "Break long lines for readability"
            )
          end
        end
      end

      def check_comments(code)
        total_lines = code.lines.size
        comment_lines = code.lines.count { |l| l.strip.start_with?('#') }
        
        if total_lines > 100 && comment_lines.to_f / total_lines < 0.05
          add_finding(
            severity: :info,
            category: :style,
            message: "Low comment ratio (#{comment_lines}/#{total_lines})",
            suggestion: "Add comments for complex logic and public APIs"
          )
        end
      end
    end
  end
end
