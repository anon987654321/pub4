# frozen_string_literal: true
require "yaml"

module Master
  module Scan
    module Rules
      # Reads anti_patterns block from data/rules.yml; emits forbidden findings as
      # critical, discouraged as warning. Single source of truth — no Ruby regex literals.
      class AntiPatternRule
        ID = :anti_pattern

        def initialize(rules_path: File.join(Master::ROOT, "data", "rules.yml"))
          data = Master.load_yaml(rules_path) || {}
          ap = data["anti_patterns"] || {}
          @forbidden   = (ap["forbidden"] || []).map   { |h| compile(h) }.compact
          @discouraged = (ap["discouraged"] || []).map { |h| compile(h) }.compact
        end

        def check(code, path:)
          findings = []
          @forbidden.each do |pat, reason|
            code.each_line.with_index(1) do |line, n|
              next unless line.match?(pat)
              findings << {rule: ID, severity: :critical, line: n, message: "anti-pattern: #{reason}"}
              break
            end
          end
          @discouraged.each do |pat, reason|
            code.each_line.with_index(1) do |line, n|
              next unless line.match?(pat)
              findings << {rule: ID, severity: :warning, line: n, message: "discouraged: #{reason}"}
              break
            end
          end
          findings
        end

        private

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
