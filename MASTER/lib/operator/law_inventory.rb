# frozen_string_literal: true

require "json"
require_relative "../io/exec"

module Operator
  # Derived intelligence over the existing law sources. It owns no rule data.
  #
  # data/laws.yml remains the catalogue; law/ remains executable law; the scan
  # registry, council and PATH_OWNERSHIP remain their own authorities. This reader
  # joins them for operator questions that otherwise require several greps.
  module LawInventory
    ROOT = File.expand_path("../../..", __dir__)
    MASTER = File.join(ROOT, "MASTER")
    LAW_ROOT = File.join(MASTER, "law")

    module_function

    def all(deep: false)
      law_rules = load_law
      registry = load_registry
      catalogue = catalogue_rows
      councils = council_rows
      deps = rule_dependencies

      ids = (catalogue.keys | law_rules.keys | registry.keys).sort
      ids.to_h do |id|
        rule = law_rules[id]
        scan = registry[id]
        row = catalogue[id] || {}
        # Keys are folded for lookup; the row names the Law as its source spells it.
        [id, {
          id: (rule&.id || row["id"] || scan&.id || id).to_s,
          name: row["name"],
          tier: row["tier"],
          severity: (rule&.severity || row["severity"])&.to_s,
          mode: rule&.mode&.to_s,
          languages: Array(rule&.languages).map(&:to_s),
          scope: rule&.scope&.to_s,
          executable_law: !rule.nil?,
          scanner: !scan.nil?,
          semantic: !!rule&.ask,
          practice: !!rule&.practice,
          fixture: rule ? !rule.bad.to_s.empty? && !rule.good.to_s.empty? : fixture_on_registry?(scan),
          successor: first_present(row["successor"], row["successor_ids"]),
          dependencies: Array(deps[id]),
          council_axes: councils.filter_map do |persona|
            emphasizes = Array(persona["emphasizes"]).map(&:to_s)
            emphasizes if source_mentions_any?(rule, emphasizes)
          end.flatten.uniq.sort,
          source: rule&.source || row["source"],
          fix: rule&.fix || row["fix"],
          health: deep ? reach(id) : {},
        }]
      end
    end

    # Reach is measured for the one row asked about: across every row it scanned
    # the corpus once per Law per row, and a single health query never finished.
    def one(id, deep: false)
      row = all.values.find { |item| item[:id].to_s.casecmp?(id.to_s) }
      deep && row ? row.merge(health: reach(row[:id])) : row
    end

    def health(id)
      row = one(id, deep: true)
      return unless row

      row.merge(
        twin: twin_status(row[:id]),
        history: history(row[:id]),
        silent_reason: silent_reason(row[:id], row[:health]),
      )
    end

    def silent
      require "operator/law_audit"
      audit = Operator::LawAudit.audit
      Array(audit[:silent]).map(&:to_s).sort
    rescue StandardError => e
      [{ "error" => "#{e.class}: #{e.message}" }]
    end

    def costly
      costs = rule_costs
      costs.sort_by { |row| [-row[:cost_ms].to_f, row[:id].to_s] }
    end

    # The three sources are read once: each read of the registry builds a scanner.
    def twins
      sources = begin
        twin_sources
      rescue StandardError
        nil
      end
      all.values.filter_map do |row|
        status = twin_status(row[:id], sources:)
        row.merge(twin: status) if status[:duplicate]
      end
    end

    def matrix
      rows = all
      personas = council_rows
      personas.map do |persona|
        axes = Array(persona["emphasizes"]).map(&:to_s)
        matches = rows.values.select { |row| (row[:council_axes] & axes).any? }.map { |row| row[:id] }
        {
          persona: persona["name"].to_s,
          axes:,
          rules: matches.sort,
        }
      end
    end

    def render(id:, deep: false, json: false)
      row = (deep ? health(id) : one(id)) if id
      return JSON.pretty_generate(row) if json
      return "rule: #{id}: not found" unless row

      lines = []
      lines << "rule: #{row[:id]}"
      lines << "  name: #{row[:name]}" if row[:name]
      lines << "  severity: #{row[:severity]}" if row[:severity]
      lines << "  mode: #{row[:mode]}" if row[:mode]
      lines << "  enforcement: #{row[:enforcement]}" if row[:enforcement]
      lines << "  languages: #{row[:languages].join(", ")}" unless row[:languages].empty?
      lines << "  scope: #{row[:scope]}" if row[:scope]
      lines << "  source: #{row[:source]}" if row[:source]
      lines << "  scanner: #{row[:scanner]}"
      lines << "  semantic: #{row[:semantic]}"
      lines << "  practice: #{row[:practice]}"
      lines << "  fixture: #{row[:fixture]}"
      lines << "  successor: #{Array(row[:successor]).join(", ")}" unless Array(row[:successor]).empty?
      lines << "  dependencies: #{Array(row[:dependencies]).join(", ")}" unless Array(row[:dependencies]).empty?
      lines << "  council_axes: #{Array(row[:council_axes]).join(", ")}" unless Array(row[:council_axes]).empty?

      if deep
        health = row[:health] || {}
        lines << "  executable_law: #{row[:executable_law]}"
        lines << "  twin: #{row[:twin][:kind]}" if row[:twin].is_a?(Hash)
        lines << "  history: #{row[:history]}" if row[:history]
        lines << "  silent_reason: #{row[:silent_reason]}" if row[:silent_reason]
        health.each { |key, value| lines << "  #{key}: #{value}" }
      end
      lines.join("\n")
    end

    def render_collection(kind, json: false)
      value = case kind
              when :silent then silent
              when :costly then costly
              when :twin then twins
              when :matrix then matrix
              else all
              end
      return JSON.pretty_generate(value) if json

      case kind
      when :silent
        Array(value).each { |id| puts "law:silent #{id}" }
        value.empty? ? "law:silent: none" : nil
      when :costly
        value.each { |row| puts "law:costly #{row[:id]} #{row[:cost_ms]}ms #{row[:samples]} sample(s)" }
        value.empty? ? "law:costly: no measured rule costs" : nil
      when :twin
        value.each { |row| puts "law:twin #{row[:id]} #{row[:twin][:kind]}" }
        value.empty? ? "law:twin: none" : nil
      when :matrix
        value.each { |row| puts "law:matrix #{row[:persona]} axes=#{row[:axes].join(",")} rules=#{row[:rules].join(",")}" }
        nil
      end
    end

    def load_law
      require File.join(MASTER, "law", "definition")
      Law.load_all(LAW_ROOT) if Law.definitions.empty?
      Law.definitions.transform_keys { |key| key.to_s.downcase }
    end

    def load_registry
      require "master"
      require "fix/scanner"
      ENV["MASTER_SCAN_DETERMINISTIC"] = "1"
      scanner = Master::Fix::Scanner.build(root: MASTER, agent: nil)
      scanner.laws.to_h { |rule| [rule.id.to_s.downcase, rule] }
    end

    # The operator's `laws ID` command needs the entire declared catalogue,
    # not only the priority-ranked entries returned by Master.law_entries.
    # Keep that recursive interpretation here and load through MASTER's sole
    # YAML reader; declarations may live under laws, beauty, anti_patterns,
    # or another nested catalogue section.
    def catalogue_declaration(id, root: MASTER)
      require "master"
      data = Master.load_laws(root:)
      raise "data/laws.yml must be a non-empty mapping" unless data.is_a?(Hash) && !data.empty?

      catalogue_declarations_in(data).find { |row| row["id"].to_s.casecmp?(id.to_s) }
    end

    def catalogue_declarations_in(node, found = [])
      case node
      when Hash
        found << node if node["id"].is_a?(String)
        node.each do |key, value|
          if key.to_s.match?(/\A[A-Z][A-Z0-9_]*\z/) && value.is_a?(Hash) && !value.key?("id")
            found << value.merge("id" => key.to_s)
          end
          catalogue_declarations_in(value, found)
        end
      when Array
        node.each { |value| catalogue_declarations_in(value, found) }
      end
      found
    end

    def catalogue_rows
      require "master"
      entries = Master.law_entries(root: MASTER)
      entries.each_with_object({}) do |entry, rows|
        next unless entry.is_a?(Hash) && entry["id"]

        rows[entry["id"].to_s.downcase] = entry
      end
    rescue StandardError
      {}
    end

    def council_rows
      require "master"
      raw = Master.load_yaml(Master::COUNCIL_PATH) || {}
      Array(raw.fetch("personas", []))
    rescue StandardError
      []
    end

    def rule_dependencies
      raw = Master.load_laws(root: MASTER)
      deps = raw["law_deps"] || {}
      return deps.transform_keys { |key| key.to_s.downcase }.transform_values { |value| Array(value).map(&:to_s) } if deps.is_a?(Hash)

      {}
    rescue StandardError
      {}
    end

    def first_present(*values)
      values.each do |value|
        array = Array(value)
        return array unless array.empty?
      end
      []
    end

    def source_mentions_any?(rule, axes)
      source = rule&.source.to_s.upcase
      axes.any? { |axis| source.include?(axis.to_s.upcase) }
    end

    def fixture_on_registry?(rule)
      rule.respond_to?(:bad) && !(rule.bad.to_s.empty? && rule.good.to_s.empty?)
    end

    def reach(id)
      require "operator/law_audit"
      entry = Operator::LawAudit.law.values.find { |law| law.id.to_s.casecmp?(id.to_s) }
      row = Operator::LawAudit.rate(entry) if entry&.scannable?
      return {} unless row

      {
        hits: row[:hits],
        applicable: row[:applicable],
        reach_rate: row[:rate],
      }
    rescue StandardError
      {}
    end

    def silent_reason(_id, health)
      return "no corpus with matching language/path" if health.empty?
      return "no findings in measured corpus" if health[:hits].to_i.zero?
      nil
    end

    def rule_costs
      path = File.join(MASTER, "runtime")
      return [] unless File.directory?(path)

      rows = Hash.new { |hash, id| hash[id] = [] }
      Dir.glob(File.join(path, "**", "*.ndjson")).each do |file|
        File.foreach(file) do |line|
          payload = JSON.parse(line)
          next unless payload.is_a?(Hash)
          id = payload["rule"] || payload["rule_id"]
          ms = payload["cost_ms"] || payload["duration_ms"] || payload.dig("cost", "latency_ms")
          next unless id && ms

          rows[id.to_s] << ms.to_f
        rescue JSON::ParserError
          next
        end
      end
      rows.map do |id, values|
        {
          id:,
          cost_ms: values.sum.fdiv(values.size).round(2),
          samples: values.size,
        }
      end
    end

    def twin_sources
      { catalogue: catalogue_rows.keys, law: load_law.keys, registry: load_registry.keys }
    end

    def twin_status(id, sources: nil)
      sources ||= twin_sources
      key = id.to_s.downcase
      present = %i[catalogue law registry].select { |source| sources.fetch(source).include?(key) }
      {
        duplicate: present.size > 1,
        kind: present.join("+"),
      }
    rescue StandardError
      { duplicate: false, kind: "unknown" }
    end

    def history(id)
      paths = %w[MASTER/law MASTER/data/laws.yml]
      format = "--format=%h %cs %s"
      output, status = Master::Io::Exec.capture2("git", "-C", ROOT, "log", "-n", "5", format, "--", *paths)
      return "history unavailable" unless status.success?

      matches = output.lines.grep(/#{Regexp.escape(id.to_s)}/i)
      matches.first&.strip || "no direct id match in recent law history"
    rescue StandardError
      "history unavailable"
    end
  end
end
