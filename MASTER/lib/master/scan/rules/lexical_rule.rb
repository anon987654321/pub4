# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # LexicalRule — data-driven: loads all detect_lexical rules from rules.yml
      # and applies them to the matching file language. Single class covering
      # HTML, CSS, Zsh, JavaScript, and cross-language lexical checks.
      class LexicalRule < Rule
        RULES_PATH = File.join(Master::ROOT, "data", "rules.yml").freeze

        def initialize
          super
          @id          = "lexical"
          @description = "Data-driven lexical checks from rules.yml for all file types"
          @severity    = :warning
          @axiom_tags  = [:UNIVERSAL]
          @loaded      = load_lexical_rules
        end

        def check(code, path:)
          lang = language(path)
          return [] unless lang

          @loaded
            .select { |r| r[:languages].nil? || r[:languages].include?(lang) }
            .select { |r| r[:path_match].nil? || path.include?(r[:path_match]) }
            .select { |r| r[:requires_present].nil? || code.match?(r[:requires_present]) }
            .reject { |r| r[:requires_absent] && code.match?(r[:requires_absent]) }
            .flat_map { |r| apply(r, code, path) }
        end

        private

        def load_lexical_rules
          data = Master.load_yaml(RULES_PATH)
          all  = (data["rules"] || {}).values.flatten
          all.filter_map do |r|
            next unless r["detect_lexical"] && !r["detect_lexical"].to_s.empty?
            langs = Array(r["languages"]).compact
            {
              id:               r["id"],
              message:          r["name"] || r["id"],
              pattern:          Regexp.new(r["detect_lexical"]),
              fix:              r["fix"],
              severity:         (r["severity"] || "warning").to_sym,
              languages:        langs.empty? ? nil : langs,
              path_match:       r["path_match"],
              requires_present: r["requires_present"] && Regexp.new(r["requires_present"]),
              requires_absent:  r["requires_absent"]  && Regexp.new(r["requires_absent"]),
              whole_file:       r["whole_file"] == true,
            }
          rescue RegexpError
            nil
          end.compact
        rescue StandardError => _e
          []
        end

        def apply(rule, code, path)
          return apply_whole_file(rule, code) if rule[:whole_file]
          code.each_line.with_index(1).filter_map do |line, num|
            next unless line.match?(rule[:pattern])
            { rule: rule[:id], message: rule[:message], line: num,
              severity: rule[:severity], fix: rule[:fix] }
          end
        end

        def apply_whole_file(rule, code)
          return [] unless code.match?(rule[:pattern])
          line = code.each_line.with_index(1).find { |l, _| l.match?(rule[:pattern]) }&.last || 1
          [{ rule: rule[:id], message: rule[:message], line: line,
             severity: rule[:severity], fix: rule[:fix] }]
        end
      end
    end
  end
end
