# frozen_string_literal: true

module Master
  module Ground
  # Loads and exposes rules, axioms, voice, and workflow from data/*.yml.
  class Rules
    RULES_SUBDIR = "rules"

    def initialize(root: nil)
      @root          = root || Master::ROOT
      @data_dir      = File.join(@root, "data")
      @rules_path    = File.join(@data_dir, "rules.yml")
      @soul_path     = File.join(@data_dir, "soul.yml")
      @workflow_path = File.join(@data_dir, "workflow.yml")
      @data          = load_yaml(@rules_path) || {}
      @data["rules"] = load_split_rules
      @soul_data     = load_yaml(@soul_path)     || {}
      @workflow      = load_yaml(@workflow_path) || {}
      @cache         = {}
    end

    # mtime-aware cache. Reloads automatically when data/<name>.yml changes on disk.
    def data(name)
      key  = name.to_sym
      path = File.join(@data_dir, "#{name}.yml")
      return @cache[key]&.first || {} unless File.exist?(path)

      mtime = File.mtime(path)
      cached = @cache[key]
      return cached.first if cached && cached.last >= mtime

      payload = Master.load_yaml(path) || {}
      @cache[key] = [payload, mtime]
      payload
    end

    def kernel
      @kernel ||= begin
        all_rules = (@data["rules"] || {}).values.flatten
        all_rules
          .select { |r| r["tier"] == "kernel" }
          .each_with_object({}) { |r, h| h[r["id"]] = r["name"] }
          .freeze
      end
    end

    def workflow = @workflow.freeze

    def philosophy(limit: nil)
      @philosophy ||= begin
        all_rules = (@data["rules"] || {}).values.flatten
        all_rules
          .reject { |r| r["tier"] == "kernel" }
          .map { |h| h.transform_keys(&:to_s) }
          .freeze
      end
      limit ? @philosophy.first(limit) : @philosophy
    end

    def all_rules     = @all_rules ||= (@data["rules"] || {}).values.flatten.freeze
    def rules_for_scope(scope) = (@data.dig("rules", scope.to_s) || []).freeze

    def kernel_block
      return if kernel.empty?

      pairs = kernel.map { |id, stmt| "  #{id}: #{stmt}" }.join("\n")
      "## Kernel Rules (enforced)\n#{pairs}"
    end

    def philosophy_block(limit: 5)
      items = philosophy(limit: limit)
      return if items.empty?

      top = items.map { |a| "  #{a["id"]}: #{a["name"]}" }.join("\n")
      "## Rules (top #{items.size})\n#{top}"
    end

    def voice    = @voice    ||= (@data["voice"] || {}).freeze
    def strunk   = @strunk   ||= (voice["strunk"] || {}).freeze
    def preserve = @preserve ||= (voice["preserve"] || {}).freeze

    def constitution
      @constitution ||= begin
        absolute = @soul_data["absolute"] || {}
        {
          "golden_rule"         => absolute["golden_rule"]      || @data["golden_rule"],
          "protection"          => absolute["protection_tiers"] || @data["protection"],
          "banned_output"       => voice["banned_output"],
          "anti_simulation"     => absolute["anti_simulation"]  || voice["anti_simulation"],
          "communication_style" => voice["style"]
        }.freeze
      end
    end

    def code_rules      = @code_rules      ||= (@soul_data.dig("absolute", "code_rules") || {}).freeze
    def thresholds       = @thresholds       ||= (@data["thresholds"] || {}).freeze
    def scan_depths      = @scan_depths      ||= (@data["scan_depths"] || {}).freeze
    def languages_config = @languages_config ||= (@data["languages"] || {}).freeze
    def workflow_rule(key) = @workflow.dig(key.to_s) || {}

    def lookup(id)
      id_str = id.to_s
      kernel[id_str] || philosophy.find { |a| a["id"] == id_str }&.dig("name")
    end

    def valid_id?(id) = all_ids.include?(id.to_s)
    def all_ids       = @all_ids ||= all_rules.map { |r| r["id"] }.compact.to_set.freeze
    def empty?        = @data.empty?

    private

    def load_split_rules
      dir = File.join(@data_dir, RULES_SUBDIR)
      return @data["rules"] || {} unless File.directory?(dir)
      Dir.glob(File.join(dir, "*.yml")).sort.each_with_object({}) do |f, merged|
        data = load_yaml(f) || {}
        data.each { |scope, rules| (merged[scope] ||= []).concat(Array(rules)) }
      end
    end

    def load_yaml(path)
      return unless File.exist?(path)
      Master.load_yaml(path)
    rescue StandardError => e
      Master::Ground::Swallow.log(e, context: "rules.load_yaml", path:)
      nil
    end
  end
  end
end
