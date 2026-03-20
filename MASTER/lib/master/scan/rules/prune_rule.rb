# frozen_string_literal: true

require "yaml"

module Master
  module Scan
    module Rules
      # PruneRule — flags hedge words and preamble phrases in Ruby comments.
      # Patterns loaded from data/strunk.yml — the same source Prune uses at runtime.
      # Violations signal prose debt; Sweep uses them to gate convergence.
      class PruneRule < Rule
        DATA_PATH = File.join(Master::ROOT, "data", "strunk.yml").freeze

        def initialize
          super
          @id          = "prune"
          @description = "Hedge words and preamble phrases in comments reduce clarity"
          @severity    = :warning
          @axiom_tags  = [:STRUNK_WHITE]
        end

        def check(code, path:)
          return [] unless path.end_with?(".rb")

          hedge_re    = build_hedge_re
          preamble_re = build_preamble_re

          code.each_line.with_index(1).flat_map { |line, num|
            next [] unless line.include?("#")
            findings = []
            findings << finding(line: num, message: "hedge in comment: #{line.strip}") if hedge_re&.match?(line)
            findings << finding(line: num, message: "preamble in comment: #{line.strip}") if preamble_re&.match?(line)
            findings
          }
        end

        private

        def rules
          @rules ||= File.exist?(DATA_PATH) ? YAML.safe_load_file(DATA_PATH) : {}
        rescue StandardError
          @rules = {}
        end

        # Regex from hedge pattern strings in strunk.yml.
        def build_hedge_re
          words = rules.fetch("hedges", []).map { |h| Regexp.escape(h["pattern"].to_s.gsub(/\\b/, "")) }
          return nil if words.empty?
          /\b(#{words.join("|")})\b/i
        end

        # Regex from preamble strings in strunk.yml.
        def build_preamble_re
          phrases = rules.fetch("preambles", []).map { |p| Regexp.escape(p) }
          return nil if phrases.empty?
          /\#.*(?:#{phrases.join("|")})/i
        end
      end
    end
  end
end
