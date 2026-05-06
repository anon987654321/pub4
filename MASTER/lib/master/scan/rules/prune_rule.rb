# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Hedge words and preamble phrases in comments dilute signal.
      # Applies to Ruby and shell files — both use # comments.
      # Patterns loaded from data/rules.yml (voice.strunk section).
      class PruneRule < Rule
        DATA_PATH   = File.join(Master::ROOT, "data", "rules.yml").freeze
        COMMENT_EXT = %w[.rb .sh .zsh .bash].freeze

        def initialize
          super
          @id          = "prune"
          @description = "Hedge words and preamble phrases in comments reduce clarity"
          @severity    = :warning
          @axiom_tags  = [:STRUNK_WHITE]
        end

        def check(code, path:)
          return [] unless COMMENT_EXT.include?(File.extname(path).downcase)

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
          @rules ||= begin
            data = File.exist?(DATA_PATH) ? Master.load_yaml(DATA_PATH) : {}
            data.dig("voice", "strunk") || {}
          end
        rescue StandardError => _e
          @rules = {}
        end

        def build_hedge_re
          words = rules.fetch("hedges", []).filter_map { |h|
            if h.is_a?(Hash)
              pat = h["pattern"].to_s.strip
              pat.empty? ? nil : Regexp.escape(pat)
            elsif h.is_a?(String)
              h.strip.empty? ? nil : Regexp.escape(h.strip)
            end
          }
          return if words.empty?
          /(#{words.join("|")})/i
        rescue StandardError => _e
          nil
        end

        def build_preamble_re
          phrases = rules.fetch("preambles", []).filter_map { |p|
            next unless p.is_a?(String)
            p.strip.empty? ? nil : Regexp.escape(p.strip)
          }
          return if phrases.empty?
          /\#.*(?:#{phrases.join("|")})/i
        rescue StandardError => _e
          nil
        end
      end
    end
  end
end
