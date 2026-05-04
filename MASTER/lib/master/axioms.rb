# frozen_string_literal: true

module Master
  # Loads and exposes rules, axioms, voice, and workflow from data/*.yml.
  class Axioms
    DATA_PATH     = File.join(File.expand_path("../../..", __dir__), "data", "rules.yml").freeze
    WORKFLOW_PATH = File.join(File.expand_path("../../..", __dir__), "data", "workflow.yml").freeze

    def initialize(root: nil)
      @rules_path    = root ? File.join(root, "data", "rules.yml")    : DATA_PATH
      @workflow_path = root ? File.join(root, "data", "workflow.yml") : WORKFLOW_PATH
      @data          = load_yaml(@rules_path)    || {}
      @workflow      = load_yaml(@workflow_path) || {}
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

    def workflow
      @workflow.freeze
    end

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

    def all_rules
      @all_rules ||= (@data["rules"] || {}).values.flatten.freeze
    end

    def rules_for_scope(scope)
      (@data.dig("rules", scope.to_s) || []).freeze
    end

    def kernel_block
      return nil if kernel.empty?

      pairs = kernel.map { |id, stmt| "  #{id}: #{stmt}" }.join("\n")
      "## Kernel Rules (enforced)\n#{pairs}"
    end

    def philosophy_block(limit: 5)
      items = philosophy(limit: limit)
      return nil if items.empty?

      top = items.map { |a| "  #{a["id"]}: #{a["name"]}" }.join("\n")
      "## Rules (top #{items.size})\n#{top}"
    end

    def voice
      @voice ||= (@data["voice"] || {}).freeze
    end

    def strunk
      @strunk ||= (voice["strunk"] || {}).freeze
    end

    def preserve
      @preserve ||= (voice["preserve"] || {}).freeze
    end

    def constitution
      @constitution ||= begin
        constitution_data = {}
        constitution_data["golden_rule"]         = @data["golden_rule"]
        constitution_data["protection"]          = @data["protection"]
        constitution_data["banned_output"]       = voice["banned_output"]
        constitution_data["anti_simulation"]     = voice["anti_simulation"]
        constitution_data["communication_style"] = voice["style"]
        constitution_data.freeze
      end
    end

    def thresholds
      @thresholds ||= (@data["thresholds"] || {}).freeze
    end

    def scan_depths
      @scan_depths ||= (@data["scan_depths"] || {}).freeze
    end

    def languages_config
      @languages_config ||= (@data["languages"] || {}).freeze
    end

    def workflow_rule(key)
      @workflow.dig(key.to_s) || {}
    end

    def lookup(id)
      id_str = id.to_s
      kernel[id_str] || philosophy.find { |a| a["id"] == id_str }&.dig("name")
    end

    def valid_id?(id)
      id_str = id.to_s
      all_ids.include?(id_str)
    end

    def all_ids
      @all_ids ||= all_rules.map { |r| r["id"] }.compact.to_set.freeze
    end

    def empty?
      @data.empty?
    end

    private

    def load_yaml(path)
      return nil unless File.exist?(path)

      Master.load_yaml(path)
    rescue StandardError => _e
      nil
    end
  end
end
