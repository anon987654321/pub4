# frozen_string_literal: true

require_relative 'enforcement'
require_relative 'code_review'
require_relative 'violations'

module MASTER
  # SelfEnforce - Axiom compliance orchestrator
  # Single entry point for all axiom enforcement operations
  module SelfEnforce
    extend self

    # Run full compliance check on code
    def check(code, filename: 'code', axioms: nil)
      axioms ||= DB.axioms

      {
        enforcement: Enforcement.check(code, axioms: axioms, filename: filename),
        code_review: CodeReview.analyze(code),
        violations: Violations.check(code, axioms: axioms),
        summary: build_summary(code, filename),
      }
    end

    # Run compliance check on entire framework
    def check_framework(files, axioms: nil)
      axioms ||= DB.axioms
      Enforcement.analyze_framework(files, axioms: axioms)
    end

    # Generate compliance report
    def report(results)
      lines = ["# Axiom Compliance Report", '']

      if results[:enforcement]
        lines << "## Enforcement Violations: #{results[:enforcement][:violations].size}"
        results[:enforcement][:violations].each do |v|
          lines << "  - #{v[:layer]}: #{v[:message]}"
        end
        lines << ''
      end

      if results[:code_review]
        lines << "## Code Review Issues: #{results[:code_review].size}"
        results[:code_review].each do |issue|
          lines << "  - #{issue[:smell]}: #{issue[:message]}"
        end
        lines << ''
      end

      if results[:violations]
        lines << "## Axiom Violations: #{results[:violations].size}"
        results[:violations].each do |v|
          lines << "  - #{v[:axiom_id]}: #{v[:message]}"
        end
        lines << ''
      end

      if results[:summary]
        lines << '## Summary'
        lines << "  Comment density: #{results[:summary][:comment_density]}%"
        lines << "  File size: #{results[:summary][:file_size]} lines"
        lines << "  Target: <#{results[:summary][:target_max_lines]} lines"
        lines << ''
      end

      lines.join("\n")
    end

    # Check if code meets ultra-minimalism requirements
    def ultra_minimal?(code, filename: 'code')
      summary = build_summary(code, filename)

      summary[:comment_density] < 5.0 &&
        summary[:file_size] < summary[:target_max_lines]
    end

    private

    def build_summary(code, filename)
      lines = code.lines
      comment_lines = lines.count { |line| line.strip.start_with?('#') }
      code_lines = lines.count { |line| !line.strip.empty? && !line.strip.start_with?('#') }

      {
        file_size: lines.size,
        code_lines: code_lines,
        comment_lines: comment_lines,
        comment_density: code_lines.zero? ? 0.0 : (comment_lines.to_f / code_lines * 100).round(2),
        target_max_lines: filename.end_with?('.rb') ? 250 : 500,
        filename: filename,
      }
    end
  end
end
