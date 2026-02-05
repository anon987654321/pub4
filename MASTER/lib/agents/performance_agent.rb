# frozen_string_literal: true

require_relative 'base_agent'

module MASTER
  module Agents
    class PerformanceAgent < BaseAgent
      LOOP_PATTERN = /\b(each|for|while|until)\b/.freeze

      def analyze(code, file_path = nil)
        clear_findings

        if code.match?(/while\s+true|loop do/)
          add_finding(
            severity: :medium,
            category: :performance,
            message: "Potential infinite loop detected",
            suggestion: "Ensure loop has a clear exit condition"
          )
        end

        loop_count = code.scan(LOOP_PATTERN).size
        if loop_count > 5
          add_finding(
            severity: :low,
            category: :performance,
            message: "High loop count (#{loop_count}) in #{file_path || 'file'}",
            suggestion: "Review for nested loops or unnecessary iteration"
          )
        end

        if code.match?(/sleep\s*\(/)
          add_finding(
            severity: :low,
            category: :performance,
            message: "Blocking sleep detected",
            suggestion: "Avoid sleep calls in performance-critical paths"
          )
        end

        @findings
      end
    end
  end
end
