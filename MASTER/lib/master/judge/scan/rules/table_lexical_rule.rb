# frozen_string_literal: true

module Master
  module Judge
  module Scan
  module Rules
  # Loads detect_lexical patterns from data/rules.yml and runs them per line.
  # Simple regex-only rules belong in lexical_rules.rb (DSL); this class
  # exists solely for the rules.yml detect_lexical axis.
  class TableLexicalRule < Rule
    RULES_PATH = File.join(Master::ROOT, "data", "rules.yml").freeze

    LANG_EXTS = {
      "ruby"       => %w[.rb .rake .gemspec],
      "zsh"        => %w[.zsh .sh],
      "html"       => %w[.html .htm .erb],
      "css"        => %w[.css .scss .sass],
      "javascript" => %w[.js .ts .jsx .tsx],
      "yaml"       => %w[.yml .yaml],
      "markdown"   => %w[.md],
    }.freeze
    ALL_EXTS = LANG_EXTS.values.flatten.freeze

    def initialize
      super
      @id = "table_lexical"; @description = "rules.yml detect_lexical patterns"
      @severity = :warning; @rule_tags = []; @entries = load_entries
    end

    def check(code, path:)
      @entries.flat_map { |e| run_entry(e, code, path) }
    end

    private

    def load_entries
      data = Master.load_yaml(RULES_PATH)
      all  = (data&.dig("rules") || {}).values.flatten
      all.filter_map { |r| compile(r) if r.is_a?(Hash) && r["detect_lexical"] }
    rescue StandardError
      []
    end

    def compile(row)
      pattern = row["detect_lexical"]
      return nil if pattern.nil? || pattern.empty? || pattern.include?("\\n")
      langs = row["languages"]
      exts  = langs ? langs.flat_map { |l| LANG_EXTS[l.to_s] || [] } : ALL_EXTS
      return nil if exts.empty?
      first  = pattern.include?("\\A")
      absent = row["requires_absent"] ? Regexp.new(row["requires_absent"]) : nil
      { id: row["id"]&.downcase || "unknown", severity: (row["severity"] || "warning").to_sym,
        langs: exts, first_line: first, path_match: row["path_match"],
        requires_absent: absent, whole_file: row["whole_file"] == true,
        re: Regexp.new(pattern), msg: row["name"] || row["id"] }
    rescue RegexpError
      nil
    end

    def run_entry(e, code, path)
      return [] unless e[:langs].include?(File.extname(path).downcase)
      return [] if e[:path_match] && !path.include?(e[:path_match])
      return [] if e[:requires_absent] && e[:whole_file] && code.match?(e[:requires_absent])
      e[:first_line] ? check_first_line(e, code) : scan_all(e, code)
    end

    def check_first_line(e, code)
      first = code.lines.first.to_s
      first.match?(e[:re]) ? [] : [emit(e, 1)]
    end

    def scan_all(e, code)
      code.each_line.with_index(1).filter_map { |line, n|
        next if e[:requires_absent] && !e[:whole_file] && line.match?(e[:requires_absent])
        emit(e, n) if line.match?(e[:re])
      }
    end

    def emit(e, line)
      { rule: e[:id], message: e[:msg], line:, severity: e[:severity], fix: nil, tags: [] }
    end
  end
  end
  end
  end
end
