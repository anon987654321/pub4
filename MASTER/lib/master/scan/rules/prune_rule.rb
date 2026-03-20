# frozen_string_literal: true

require "yaml"

module Master
  module Scan
    module Rules
      # PruneRule — flags hedge words and preamble phrases in Ruby comments.
      # Patterns loaded from data/strunk.yml — the same source the Prune stage uses at runtime.
      # Single source of truth: no hardcoded patterns here.
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
            findings << finding(line: num, message: "hedge in comment: #{line.strip}")    if hedge_re&.match?(line)
            findings << finding(line: num, message: "preamble in comment: #{line.strip}") if preamble_re&.match?(line)
            findings
          }
        end

        private

        def rules
          @rules ||= (File.exist?(DATA_PATH) ? YAML.safe_load_file(DATA_PATH) : nil) || {}
        rescue StandardError
          @rules = {}
        end

        # Build regex from hedge entries in strunk.yml: [{pattern:, replace:}, ...].
        def build_hedge_re
          words = rules.fetch("hedges", []).filter_map { |h|
            next unless h.is_a?(Hash)
            pat = h["pattern"].to_s.strip
            pat.empty? ? nil : Regexp.escape(pat)
          }
          return nil if words.empty?
          /(#{words.join("|")})/i
        rescue StandardError
          nil
        end

        # Build regex from preamble strings in strunk.yml.
        def build_preamble_re
          phrases = rules.fetch("preambles", []).filter_map { |p|
            next unless p.is_a?(String)
            p.strip.empty? ? nil : Regexp.escape(p.strip)
          }
          return nil if phrases.empty?
          /\#.*(?:#{phrases.join("|")})/i
        rescue StandardError
          nil
        end
      end
    end
  end
end
