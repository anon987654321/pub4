# frozen_string_literal: true

require 'yaml'

# 8-phase bug hunting protocol from v38
module MASTER
  module Unified
    class BugHunting
      PHASES = %i[
        lexical_consistency
        simulated_execution
        assumption_interrogation
        data_flow_analysis
        state_archaeology
        pattern_recognition
        proof_of_understanding
        verification
      ].freeze

      attr_reader :current_phase, :findings

      def initialize(file_path)
        @file_path = file_path
        @current_phase = 0
        @findings = []
        @content = File.exist?(file_path) ? File.read(file_path) : ""
      end

      def analyze(options = {})
        results = {
          file: @file_path,
          timestamp: Time.now,
          phases: {}
        }

        PHASES.each_with_index do |phase, index|
          @current_phase = index
          phase_result = send("phase_#{phase}")
          results[:phases][phase] = phase_result
          @findings += phase_result[:issues] if phase_result[:issues]
        end

        results[:total_issues] = @findings.length
        results[:severity] = calculate_severity
        
        results
      end

      def self.analyze_file(file_path, options = {})
        new(file_path).analyze(options)
      end

      private

      # Phase 1: Lexical Consistency
      def phase_lexical_consistency
        issues = []
        
        # Check for undefined variables (simple heuristic)
        undefined_vars = find_undefined_variables
        issues += undefined_vars.map { |var| 
          { type: "undefined_variable", variable: var, severity: :high }
        }
        
        # Check for case sensitivity issues
        case_issues = find_case_sensitivity_issues
        issues += case_issues
        
        # Check for common typos
        typos = find_common_typos
        issues += typos
        
        {
          phase: "Lexical Consistency",
          description: "Variable naming, typos, case sensitivity",
          issues: issues,
          passed: issues.empty?
        }
      end

      # Phase 2: Simulated Execution
      def phase_simulated_execution
        issues = []
        
        # Trace control flow
        control_flow = analyze_control_flow
        issues << { 
          type: "control_flow", 
          analysis: control_flow,
          severity: :info
        }
        
        {
          phase: "Simulated Execution",
          description: "Trace control flow and state changes",
          issues: issues,
          passed: true
        }
      end

      # Phase 3: Assumption Interrogation
      def phase_assumption_interrogation
        assumptions = []
        
        # Find assertions and validations
        validations = find_validations
        assumptions << {
          type: "input_validation",
          count: validations.length,
          severity: validations.empty? ? :medium : :info
        }
        
        {
          phase: "Assumption Interrogation",
          description: "Challenge every assumption",
          issues: assumptions,
          passed: true
        }
      end

      # Phase 4: Data Flow Analysis
      def phase_data_flow_analysis
        issues = []
        
        # Track variable assignments and usage
        data_flow = analyze_data_flow
        issues << {
          type: "data_flow",
          variables: data_flow,
          severity: :info
        }
        
        {
          phase: "Data Flow Analysis",
          description: "Track data from source to sink",
          issues: issues,
          passed: true
        }
      end

      # Phase 5: State Archaeology
      def phase_state_archaeology
        issues = []
        
        # Check for git history if available
        if File.directory?(File.join(File.dirname(@file_path), ".git"))
          recent_changes = check_git_history
          issues << {
            type: "recent_changes",
            changes: recent_changes,
            severity: :info
          }
        end
        
        {
          phase: "State Archaeology",
          description: "Examine system state before/after failure",
          issues: issues,
          passed: true
        }
      end

      # Phase 6: Pattern Recognition
      def phase_pattern_recognition
        issues = []
        
        # Check for common bug patterns
        patterns = [
          { name: "off_by_one", pattern: /\w+\s*[-+]\s*1\b/ },
          { name: "null_check", pattern: /if\s+\w+\.nil\?/ },
          { name: "empty_check", pattern: /\.empty\?/ },
          { name: "rescue_bare", pattern: /rescue\s*$/ }
        ]
        
        patterns.each do |p|
          matches = @content.scan(p[:pattern])
          if matches.any?
            issues << {
              type: "pattern_found",
              pattern: p[:name],
              count: matches.length,
              severity: :low
            }
          end
        end
        
        {
          phase: "Pattern Recognition",
          description: "Compare to known bug patterns",
          issues: issues,
          passed: true
        }
      end

      # Phase 7: Proof of Understanding
      def phase_proof_of_understanding
        {
          phase: "Proof of Understanding",
          description: "Demonstrate understanding of the bug",
          issues: [],
          passed: true,
          note: "Requires manual verification"
        }
      end

      # Phase 8: Verification
      def phase_verification
        {
          phase: "Verification",
          description: "Prove the fix works",
          issues: [],
          passed: true,
          note: "Run tests to verify"
        }
      end

      # Helper methods
      def find_undefined_variables
        # Simple heuristic: look for common patterns
        []  # Placeholder - would need AST parsing for accuracy
      end

      def find_case_sensitivity_issues
        []  # Placeholder
      end

      def find_common_typos
        typos = []
        
        # Common Ruby typos
        typo_patterns = {
          'lenth' => 'length',
          'inlcude' => 'include',
          'reponse' => 'response',
          'recieve' => 'receive'
        }
        
        typo_patterns.each do |typo, correct|
          if @content.include?(typo)
            typos << {
              type: "typo",
              found: typo,
              should_be: correct,
              severity: :high
            }
          end
        end
        
        typos
      end

      def analyze_control_flow
        {
          methods: count_methods,
          conditionals: count_conditionals,
          loops: count_loops
        }
      end

      def find_validations
        validations = []
        
        # Look for common validation patterns
        patterns = [
          /raise\s+.*if/,
          /return.*unless/,
          /validates?/
        ]
        
        patterns.each do |pattern|
          validations += @content.scan(pattern)
        end
        
        validations
      end

      def analyze_data_flow
        {
          assignments: @content.scan(/\w+\s*=/).length,
          method_calls: @content.scan(/\w+\(/).length
        }
      end

      def check_git_history
        # Would use git commands here
        []
      end

      def count_methods
        @content.scan(/def\s+\w+/).length
      end

      def count_conditionals
        @content.scan(/\b(if|unless|case)\b/).length
      end

      def count_loops
        @content.scan(/\b(while|until|loop|each|map)\b/).length
      end

      def calculate_severity
        high = @findings.count { |f| f[:severity] == :high }
        medium = @findings.count { |f| f[:severity] == :medium }
        
        return :critical if high > 5
        return :high if high > 0
        return :medium if medium > 0
        :low
      end
    end
  end
end
