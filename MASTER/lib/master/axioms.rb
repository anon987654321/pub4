# frozen_string_literal: true

require "yaml"

module Master
  # Central source for rules, axioms, voice, and workflow.
  # Loads from data/rules.yml (unified hierarchy) and data/workflow.yml.
  # All data is loaded once (optionally from a custom root) and frozen
  # to guarantee immutability and fast repeated access.
  class Axioms
    DATA_PATH     = File.join(File.expand_path("../../..", __dir__), "data", "rules.yml").freeze
    WORKFLOW_PATH = File.join(File.expand_path("../../..", __dir__), "data", "workflow.yml").freeze

    def initialize(root: nil)
      @rules_path    = root ? File.join(root, "data", "rules.yml")    : DATA_PATH
      @workflow_path = root ? File.join(root, "data", "workflow.yml") : WORKFLOW_PATH
      @data          = load_yaml(@rules_path)    || {}
      @workflow      = load_yaml(@workflow_path) || {}
    end

    # Public API ---------------------------------------------------------

    # Kernel rules: {ID => name} hash for backward compatibility.
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

    # All non-kernel rules as an array of hashes.
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

    # All rules across all scopes, flat array.
    def all_rules
      @all_rules ||= (@data["rules"] || {}).values.flatten.freeze
    end

    # Rules filtered by scope: codebase, file, unit, line.
    def rules_for_scope(scope)
      (@data.dig("rules", scope.to_s) || []).freeze
    end

    # Formatted blocks for display (e.g. in prompts) --------------------

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

    # Voice, strunk, constitution ----------------------------------------

    def voice
      @voice ||= (@data["voice"] || {}).freeze
    end

    def strunk
      @strunk ||= (voice["strunk"] || {}).freeze
    end

    def constitution
      @constitution ||= begin
        c = {}
        c["golden_rule"] = @data["golden_rule"]
        c["protection"] = @data["protection"]
        c["banned_output"] = voice["banned_output"]
        c["anti_simulation"] = voice["anti_simulation"]
        c["communication_style"] = voice["style"]
        c.freeze
      end
    end

    # Thresholds, scan depths, language config ---------------------------

    def thresholds
      @thresholds ||= (@data["thresholds"] || {}).freeze
    end

    def scan_depths
      @scan_depths ||= (@data["scan_depths"] || {}).freeze
    end

    def languages_config
      @languages_config ||= (@data["languages"] || {}).freeze
    end

    # Workflow rule lookup ------------------------------------------------

    def workflow_rule(key)
      @workflow.dig(key.to_s) || {}
    end

    # General lookup -------------------------------------------------------

    def lookup(id)
      id_str = id.to_s
      kernel[id_str] ||
        philosophy.find { |a| a["id"] == id_str }&.dig("name")
    end

    def empty?
      @data.empty?
    end

    # ---------------------------------------------------------------------

    private

    def load_yaml(path)
      return nil unless File.exist?(path)

      YAML.safe_load_file(path, permitted_classes: [], permitted_symbols: [], aliases: true)
    rescue StandardError
      nil
    end
  end
end
