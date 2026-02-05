# frozen_string_literal: true

module MASTER
  module Agents
    class ArchitectureAgent < BaseAgent
      def analyze(code, file_path = nil)
        clear_findings
        
        # Analyze coupling
        check_coupling(code)

        # Analyze cohesion
        check_cohesion(code)

        # Check architectural patterns
        check_architectural_patterns(code, file_path)

        # Analyze dependencies
        check_dependencies(code)

        @findings
      end

      private

      def check_coupling(code)
        # Count external dependencies
        requires = code.scan(/require\s+['"]([^'"]+)['"]/).flatten
        
        if requires.size > 15
          add_finding(
            severity: :high,
            category: :architecture,
            message: "High coupling detected: #{requires.size} dependencies",
            suggestion: "Consider splitting into multiple files or reducing dependencies"
          )
        end

        # Check for tight coupling patterns
        if code.match?(/\.constantize|\.send\(/i)
          add_finding(
            severity: :medium,
            category: :architecture,
            message: "Dynamic coupling detected (constantize/send)",
            suggestion: "Use dependency injection or explicit interfaces"
          )
        end

        # Check for global state
        if code.match?(/\$\w+\s*=|\$\w+\.|global/i)
          add_finding(
            severity: :high,
            category: :architecture,
            message: "Global state usage detected",
            suggestion: "Refactor to use dependency injection (Principle: DIP)"
          )
        end
      end

      def check_cohesion(code)
        # Analyze class responsibilities
        classes = code.scan(/class\s+(\w+).*?(?=\nclass\s|\z)/m)
        
        classes.each do |class_match|
          class_body = $&
          class_name = class_match[0]
          
          # Count public methods
          public_methods = class_body.scan(/^\s+def\s+(\w+)/).flatten
          instance_vars = class_body.scan(/@(\w+)/).flatten.uniq
          
          if public_methods.size > 10
            add_finding(
              severity: :medium,
              category: :architecture,
              message: "Class '#{class_name}' has many public methods (#{public_methods.size})",
              suggestion: "Consider splitting responsibilities (Principle: SRP)"
            )
          end

          if instance_vars.size > 7
            add_finding(
              severity: :medium,
              category: :architecture,
              message: "Class '#{class_name}' has many instance variables (#{instance_vars.size})",
              suggestion: "High state complexity - consider refactoring"
            )
          end
        end
      end

      def check_architectural_patterns(code, file_path)
        # Check for God Object anti-pattern
        if code.lines.size > 500
          add_finding(
            severity: :high,
            category: :architecture,
            message: "Very large file (#{code.lines.size} lines) - potential God Object",
            suggestion: "Split into multiple focused classes"
          )
        end

        # Check for proper separation of concerns
        has_db_logic = code.match?(/ActiveRecord|query|sql/i)
        has_view_logic = code.match?(/render|html|erb/i)
        has_business_logic = code.match?(/validate|process|calculate/i)

        if [has_db_logic, has_view_logic, has_business_logic].count(true) > 1
          add_finding(
            severity: :medium,
            category: :architecture,
            message: "Mixed concerns detected (DB + View + Business Logic)",
            suggestion: "Separate into layers (Principle: Separation of Concerns)"
          )
        end

        # Check for anemic domain model
        if code.match?(/class\s+\w+.*attr_accessor.*end/m) && !code.match?(/def\s+\w+/)
          add_finding(
            severity: :low,
            category: :architecture,
            message: "Anemic domain model - class with only data, no behavior",
            suggestion: "Add domain logic methods to encapsulate behavior"
          )
        end
      end

      def check_dependencies(code)
        # Check for circular dependency indicators
        if code.match?(/require_relative.*\.\.\//i)
          add_finding(
            severity: :medium,
            category: :architecture,
            message: "Upward relative require - potential circular dependency",
            suggestion: "Review module structure and dependencies"
          )
        end

        # Check for dependency on concrete implementations
        if code.match?(/new\s+[A-Z]\w+\(/i)
          concrete_deps = code.scan(/new\s+([A-Z]\w+)\(/i).flatten.uniq
          if concrete_deps.size > 5
            add_finding(
              severity: :medium,
              category: :architecture,
              message: "Many concrete dependencies (#{concrete_deps.size})",
              suggestion: "Consider dependency injection (Principle: DIP)"
            )
          end
        end
      end
    end
  end
end
