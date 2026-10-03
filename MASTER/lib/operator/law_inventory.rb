# frozen_string_literal: true

require "json"
require "open3"
require "yaml"

module Operator
  # Derived intelligence over the existing law sources. It owns no rule data.
  #
  # data/rules.yml remains the catalogue; law/ remains executable law; the scan
  # registry, council and PATH_OWNERSHIP remain their own authorities. This reader
  # joins them for operator questions that otherwise require several greps.
  module LawInventory
    ROOT = File.expand_path("../../..", __dir__)
    MASTER = File.join(ROOT, "MASTER")
    LAW_ROOT = File.join(MASTER, "law")
    RULES_PATH = File.join(MASTER, "data", "rules.yml")
    COUNCIL_PATH = File.join(MASTER, "data", "council.yml")

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
        {
          id:,
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
        }
      end
    end

    def one(id, deep: false)
      key = id.to_s.downcase
      rows = all(deep:)
      rows.values.find { |row| row[:id].to_s.downcase == key }
    end

    def health(id)
      row = one(id, deep: true)
      return unless row

      row.merge(
        twin: twin_status(row[:id]),
        history: history(row[:id]),
        silent_reason: silent_reason(row[:id], row[:health])
      )
    end

    def silent
      require "operator/rule_audit"
      audit = Operator::RuleAudit.audit
      Array(audit[:silent]).map(&:to_s).sort
    rescue StandardError => e
      [{ "error" => "#{e.class}: #{e.message}" }]
    end

    def costly
      costs = rule_costs
      costs.sort_by { |row| [-row[:cost_ms].to_f, row[:id].to_s] }
    end

    def twins
      ids = all.values
      ids.filter_map do |row|
        status = twin_status(row[:id])
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
          rules: matches.sort
        }
      end
    end

    def render(id:, deep: false, json: false)
      row = id ? (deep ? health(id) : one(id)) : nil
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
      require File.join(MASTER, "law", "law")
      Law.load_all(LAW_ROOT) if Law.rules.empty?
      Law.rules.transform_keys { |key| key.to_s.downcase }
    end

    def load_registry
      require "master"
      require "review/scan/infra_helpers"
      ENV["MASTER_SCAN_DETERMINISTIC"] = "1"
      scanner = Master::Review::Scan::InfraHelpers.build_scanner(root: MASTER, agent: nil)
      scanner.rules.to_h { |rule| [rule.id.to_s.downcase, rule] }
    end

    def catalogue_rows
      require "master"
      raw = Master.load_rules(root: MASTER)
      entries = Master.flatten_rules(raw.fetch("rules", {}))
      entries.each_with_object({}) do |entry, rows|
        next unless entry.is_a?(Hash) && entry["id"]

        rows[entry["id"].to_s.downcase] = entry
      end
    rescue StandardError
      {}
    end

    def council_rows
      raw = YAML.safe_load_file(COUNCIL_PATH, aliases: true) || {}
      Array(raw.fetch("personas", []))
    rescue StandardError
      []
    end

    def rule_dependencies
      raw = Master.load_rules(root: MASTER)
      deps = raw["rule_deps"] || {}
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
      rule.respond_to?(:dsl_fires) && (rule.dsl_fires || rule.dsl_does_not_fire)
    end

    def reach(id)
      require "operator/rule_audit"
      row = Operator::RuleAudit.rates.find { |item| item[:rule].to_s.downcase == id.to_s.downcase }
      return {} unless row

      {
        hits: row[:hits],
        applicable: row[:applicable],
        reach_rate: row[:rate]
      }
    rescue StandardError
      {}
    end

    def silent_reason(id, health)
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

    def twin_status(id)
      require "operator/rule_audit"
      registry = load_registry.key?(id.to_s.downcase)
      law = load_law.key?(id.to_s.downcase)
      catalogue = catalogue_rows.key?(id.to_s.downcase)
      present = [catalogue && :catalogue, law && :law, registry && :registry].compact
      {
        duplicate: present.size > 1,
        kind: present.join("+"),
      }
    rescue StandardError
      { duplicate: false, kind: "unknown" }
    end

    def history(id)
      output, status = Open3.capture2("git", "-C", ROOT, "log", "-n", "5", "--format=%h %cs %s", "--", "MASTER/law", "MASTER/data/rules.yml", "MASTER/lib/review/scan/rules")
      return "history unavailable" unless status.success?

      matches = output.lines.grep(/#{Regexp.escape(id.to_s)}/i)
      matches.first&.strip || "no direct id match in recent law history"
    rescue StandardError
      "history unavailable"
    end
  end
end
