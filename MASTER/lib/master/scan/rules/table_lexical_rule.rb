# frozen_string_literal: true

module Master
  module Scan
    module Rules
      # Table-driven adapter — replaces 30+ regex-only rules with one class that
      # reads data/lexical_rules.yml. Each table entry becomes a virtual rule with
      # its own id surfaced on every finding. Adding a new lexical rule = a yaml
      # entry, not a new Ruby file.
      class TableLexicalRule < Rule
        TABLE_PATH = File.join(Master::ROOT, "data", "lexical_rules.yml").freeze

        def initialize
          super
          @id          = "table_lexical"
          @description = "Aggregator: emits findings under the id of each matching table row"
          @severity    = :warning
          @axiom_tags  = []
          @entries     = load_entries
        end

        def check(code, path:)
          @entries.flat_map { |entry| run_entry(entry, code, path) }
        end

        private

        def load_entries
          rows = Master.load_yaml(TABLE_PATH)
          (rows || []).map { |r| compile_entry(r) }
        rescue StandardError
          []
        end

        def compile_entry(row)
          {
            id:           row["id"],
            severity:     row["severity"]&.to_sym || :warning,
            tags:         (row["axiom_tags"] || []).map(&:to_sym),
            langs:        row["langs"] || [".rb"],
            includes:     row["path_includes"],
            excludes:     row["path_excludes"],
            skip_comments: row["skip_comments"] == true,
            first_line:   row["first_line"] == true,
            patterns:     (row["patterns"] || []).map { |p|
              { re: Regexp.new(p["regex"]), msg: p["message"], negate: p["negate"] == true,
                one_per_file: p["one_per_file"] == true }
            }
          }
        end

        def run_entry(entry, code, path)
          return [] unless entry[:langs].include?(File.extname(path).downcase)
          return [] if entry[:includes] && !path.include?(entry[:includes])
          return [] if entry[:excludes] && path.include?(entry[:excludes])
          entry[:first_line] ? first_line_findings(entry, code) : per_line_findings(entry, code)
        end

        def first_line_findings(entry, code)
          first = code.lines.first.to_s
          entry[:patterns].flat_map do |p|
            matched = first.match?(p[:re])
            hit = p[:negate] ? !matched : matched
            hit ? [emit(entry, p, 1)] : []
          end
        end

        def per_line_findings(entry, code)
          findings = []
          seen_one = {}
          code.each_line.with_index(1) do |line, num|
            next if entry[:skip_comments] && line.strip.start_with?("#")
            entry[:patterns].each do |p|
              next unless line.match?(p[:re])
              next if p[:one_per_file] && seen_one[p[:re]]
              findings << emit(entry, p, num)
              seen_one[p[:re]] = true if p[:one_per_file]
            end
          end
          findings
        end

        def emit(entry, pattern, line)
          { rule: entry[:id], message: pattern[:msg], line: line,
            severity: entry[:severity], fix: nil, tags: entry[:tags] }
        end
      end
    end
  end
end
