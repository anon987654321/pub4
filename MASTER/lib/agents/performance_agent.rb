# frozen_string_literal: true

require_relative 'base_agent'

module MASTER
  module Agents
    class PerformanceAgent < BaseAgent
      LOOP_PATTERN = /\b(each|for|while|until)\b/.freeze
      INFINITE_LOOP_PATTERN = /while\s+true|loop do/.freeze
      SLEEP_PATTERN = /\bsleep\b\s*(\(|\w)/.freeze
      COMMENT_PATTERN = /#.*$/.freeze
      DOUBLE_QUOTE_PATTERN = /"[^"]*"/.freeze
      SINGLE_QUOTE_PATTERN = /'[^']*'/.freeze
      MAX_LOOP_COUNT = 5

      def analyze(code, file_path = nil)
        clear_findings

        if code.match?(INFINITE_LOOP_PATTERN)
          add_finding(
            severity: :medium,
            category: :performance,
            message: "Potential infinite loop detected",
            suggestion: "Ensure loop has a clear exit condition"
          )
        end

        loop_count = code.lines.count do |line|
          next false unless line.match?(LOOP_PATTERN)

          scrubbed = line.sub(COMMENT_PATTERN, '')
          scrubbed = scrubbed.gsub(DOUBLE_QUOTE_PATTERN, '').gsub(SINGLE_QUOTE_PATTERN, '')
          scrubbed.match?(LOOP_PATTERN)
        end
        if loop_count > MAX_LOOP_COUNT
          add_finding(
            severity: :low,
            category: :performance,
            message: "High loop count (#{loop_count}) in #{file_path || 'unknown file'}",
            suggestion: "Review for nested loops or unnecessary iteration"
          )
        end

        if code.match?(SLEEP_PATTERN)
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
