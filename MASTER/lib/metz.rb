#!/usr/bin/env ruby
# frozen_string_literal: true

module MASTER
  # Sandi Metz quality rules
  # 100/5/4/1: 100 lines per class, 5 lines per method, 4 params, 1 object per view
  module Metz
    RULES = {
      class_lines: 100,
      method_lines: 5,
      method_params: 4,
      instance_vars: 4,
    }.freeze

    class << self
      # Check if file passes Metz rules
      def check(file_path)
        content = File.read(file_path)
        
        violations = []
        violations += check_class_length(content)
        violations += check_method_length(content)
        violations += check_method_params(content)
        violations += check_instance_vars(content)
        
        {
          file: file_path,
          passed: violations.empty?,
          violations: violations,
          score: calculate_score(violations)
        }
      end

      # Check class length
      def check_class_length(content)
        violations = []
        
        # Find class definitions
        content.scan(/^class\s+(\w+).*?^end/m).each do |match|
          class_name = match[0]
          class_body = match[0]
          lines = class_body.split("\n").reject { |l| l.strip.empty? || l.strip.start_with?('#') }.length
          
          if lines > RULES[:class_lines]
            violations << {
              rule: 'class_lines',
              message: "Class #{class_name} has #{lines} lines (max #{RULES[:class_lines]})",
              severity: 'warning'
            }
          end
        end
        
        violations
      end

      # Check method length
      def check_method_length(content)
        violations = []
        
        # Find method definitions
        content.scan(/^\s*def\s+(\w+).*?\n(.*?)^\s*end/m).each do |match|
          method_name = match[0]
          method_body = match[1]
          lines = method_body.split("\n").reject { |l| l.strip.empty? || l.strip.start_with?('#') }.length
          
          if lines > RULES[:method_lines]
            violations << {
              rule: 'method_lines',
              message: "Method #{method_name} has #{lines} lines (max #{RULES[:method_lines]})",
              severity: 'warning'
            }
          end
        end
        
        violations
      end

      # Check method parameters
      def check_method_params(content)
        violations = []
        
        # Find method definitions with parameters
        content.scan(/^\s*def\s+(\w+)\((.*?)\)/m).each do |match|
          method_name = match[0]
          params = match[1].split(',').length
          
          if params > RULES[:method_params]
            violations << {
              rule: 'method_params',
              message: "Method #{method_name} has #{params} parameters (max #{RULES[:method_params]})",
              severity: 'warning'
            }
          end
        end
        
        violations
      end

      # Check instance variables in controllers/views
      def check_instance_vars(content)
        violations = []
        
        # This is a simplified check
        # Real implementation would track instance vars per class
        ivars = content.scan(/@\w+/).uniq
        
        if ivars.length > RULES[:instance_vars]
          violations << {
            rule: 'instance_vars',
            message: "Too many instance variables: #{ivars.length} (max #{RULES[:instance_vars]})",
            severity: 'info'
          }
        end
        
        violations
      end

      # Calculate score based on violations
      def calculate_score(violations)
        return 1.0 if violations.empty?
        
        deductions = violations.sum do |v|
          case v[:severity]
          when 'error' then 0.2
          when 'warning' then 0.1
          when 'info' then 0.05
          else 0.1
          end
        end
        
        [0.0, 1.0 - deductions].max
      end

      # Check cyclomatic complexity (simplified)
      def complexity(content)
        # Count decision points: if, unless, while, until, for, case, &&, ||, rescue
        decisions = content.scan(/\b(if|unless|while|until|for|case|&&|\|\||rescue)\b/).length
        decisions + 1  # Base complexity is 1
      end
    end
  end
end
