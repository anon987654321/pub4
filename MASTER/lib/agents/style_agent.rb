# frozen_string_literal: true

require_relative 'base_agent'

module MASTER
  module Agents
    class StyleAgent < BaseAgent
      MAX_FINDINGS = 10

      def analyze(code, file_path = nil)
        clear_findings

        code.lines.each_with_index do |line, idx|
          break if @findings.size >= MAX_FINDINGS

          if line.match?(/[ \t]+$/)
            add_finding(
              severity: :low,
              category: :style,
              message: "Trailing whitespace",
              line: idx + 1,
              suggestion: "Trim trailing whitespace"
            )
          end

          if line.include?("\t")
            add_finding(
              severity: :low,
              category: :style,
              message: "Tab indentation detected",
              line: idx + 1,
              suggestion: "Use spaces for indentation"
            )
          end

          if line.chomp.length > 120
            add_finding(
              severity: :low,
              category: :style,
              message: "Line exceeds 120 characters",
              line: idx + 1,
              suggestion: "Wrap long lines for readability"
            )
          end
        end

        @findings
      end
    end
  end
end
