# frozen_string_literal: true

module MASTER
  module Agents
    class PerformanceAgent < BaseAgent
      PERFORMANCE_PATTERNS = [
        { pattern: /\.each\s+do.*\.where\(/m, severity: :high, message: "N+1 query detected - query inside loop" },
        { pattern: /\.find\(.*\)\.each/i, severity: :high, message: "Potential N+1 - consider using includes/joins" },
        { pattern: /sleep\s*\(/i, severity: :medium, message: "Blocking sleep detected" },
        { pattern: /\+\s*=\s*["']/i, severity: :low, message: "String concatenation in loop - use array join or StringIO" },
        { pattern: /\.select.*\.map/i, severity: :low, message: "Chained select-map can be optimized" },
        { pattern: /while\s+true/i, severity: :medium, message: "Infinite loop without break condition visible" },
        { pattern: /\.each.*\.each/m, severity: :medium, message: "Nested loops detected - O(n²) complexity" },
        { pattern: /File\.read.*\.each_line/i, severity: :high, message: "Loading entire file into memory - use streaming" }
      ].freeze

      def analyze(code, file_path = nil)
        clear_findings
        
        # Pattern-based performance checks
        code.lines.each_with_index do |line, idx|
          PERFORMANCE_PATTERNS.each do |pattern_info|
            if line.match?(pattern_info[:pattern])
              add_finding(
                severity: pattern_info[:severity],
                category: :performance,
                message: pattern_info[:message],
                line: idx + 1,
                suggestion: suggest_optimization(pattern_info[:pattern], line)
              )
            end
          end
        end

        # Check for memory leaks
        check_memory_leaks(code)

        # Detect inefficient algorithms
        detect_inefficient_algorithms(code)

        @findings
      end

      private

      def check_memory_leaks(code)
        # Check for unclosed resources
        if code.match?(/File\.open/) && !code.match?(/File\.open.*\bdo\b/)
          add_finding(
            severity: :high,
            category: :performance,
            message: "File.open without block - potential resource leak",
            suggestion: "Use File.open with block to ensure file is closed"
          )
        end

        # Check for growing arrays in loops
        if code.match?(/loop\s+do.*<<|while.*<<|each.*<</m)
          add_finding(
            severity: :medium,
            category: :performance,
            message: "Array growing inside loop - consider pre-allocating",
            suggestion: "Pre-allocate array size if known, or use alternative data structure"
          )
        end
      end

      def detect_inefficient_algorithms(code)
        # Detect inefficient searches
        if code.match?(/\.each.*\.include\?/m)
          add_finding(
            severity: :medium,
            category: :performance,
            message: "Inefficient search - O(n*m) complexity",
            suggestion: "Convert to Set for O(1) lookups or use hash-based approach"
          )
        end

        # Detect repeated expensive operations
        if code.match?(/\.map.*\.map/i)
          add_finding(
            severity: :low,
            category: :performance,
            message: "Multiple passes over collection - can be combined",
            suggestion: "Combine map operations into single pass"
          )
        end
      end

      def suggest_optimization(pattern, line)
        case pattern.source
        when /N\+1|each.*where/i
          "Use eager loading: includes(), preload(), or eager_load()"
        when /select.*map/i
          "Combine into single map with conditional logic"
        when /File\.read.*each_line/i
          "Use File.foreach or File.each_line for streaming"
        when /each.*each/i
          "Consider flat_map, product, or restructure logic"
        else
          "Profile and optimize based on actual performance metrics"
        end
      end
    end
  end
end
