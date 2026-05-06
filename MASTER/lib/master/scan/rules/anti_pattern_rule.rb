# frozen_string_literal: true
require "yaml"

module Master
  module Scan
    module Rules
      # Reads anti_patterns block from data/rules.yml; emits forbidden findings as
      # critical, discouraged as warning. Single source of truth — no Ruby regex literals.
      class AntiPatternRule < Rule
        def initialize(rules_path: File.join(Master::ROOT, "data", "rules.yml"))
          super()
          @id          = "anti_pattern"
          @description = "Forbidden / discouraged patterns from data/rules.yml"
          @severity    = :critical
          @axiom_tags  = []
          data = Master.load_yaml(rules_path) || {}
          ap = data["anti_patterns"] || {}
          @forbidden   = (ap["forbidden"] || []).map   { |h| compile(h) }.compact
          @discouraged = (ap["discouraged"] || []).map { |h| compile(h) }.compact
        end

        def check(code, _path: nil, **)
          findings = []
          @forbidden.each do |pat, reason|
            line_no = first_match_line(code, pat)
            findings << finding_with(severity: :critical, line: line_no, message: "anti-pattern: #{reason}") if line_no
          end
          @discouraged.each do |pat, reason|
            line_no = first_match_line(code, pat)
            findings << finding_with(severity: :warning, line: line_no, message: "discouraged: #{reason}") if line_no
          end
          findings
        end

        private

        def first_match_line(code, pat)
          code.each_line.with_index(1) { |line, n| return n if line.match?(pat) }
          nil
        end

        def finding_with(severity:, line:, message:)
          { rule: @id, severity:, line:, message:, fix: nil }
        end

        def compile(h)
          pat = h["pattern"] || h[:pattern]
          return nil unless pat.is_a?(String)
          [Regexp.new(pat), h["reason"] || h[:reason] || "anti-pattern"]
        rescue RegexpError
          nil
        end
      end
    end
  end
end
