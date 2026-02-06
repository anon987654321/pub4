# frozen_string_literal: true

require_relative 'base_agent'

module MASTER
  module Agents
    class StyleAgent < BaseAgent
      MAX_FINDINGS = 10
      TRAILING_WHITESPACE = /[ \t]+$/.freeze
      TAB_PATTERN = /\t/.freeze

      def analyze(code, file_path = nil)
        clear_findings

        code.lines.each_with_index do |line, idx|
          break if @findings.size >= MAX_FINDINGS

          if line.match?(TRAILING_WHITESPACE)
            add_finding(
              severity: :low,
              category: :style,
              message: "Trailing whitespace",
              line: idx + 1,
              suggestion: "Trim trailing whitespace"
            )
          end

          if line.match?(TAB_PATTERN)
            line_without_trailing_whitespace = line.sub(TRAILING_WHITESPACE, '')
            if line_without_trailing_whitespace.match?(TAB_PATTERN)
              add_finding(
                severity: :low,
                category: :style,
                message: "Tab indentation detected",
                line: idx + 1,
                suggestion: "Use spaces for indentation"
              )
            end
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
