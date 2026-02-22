# frozen_string_literal: true

require "json"
require "yaml"

module MASTER
  module Review
    module DesignCodex
      module_function

      CODEX_FILE = File.join(MASTER.root, "data", "design_codex.yml")

      def rules
        @rules ||= if File.exist?(CODEX_FILE)
          YAML.safe_load_file(CODEX_FILE, symbolize_names: true) || {}
        else
          {}
        end
      end

      def reload!
        @rules = nil
        rules
      end

      def section(name)
        rules[name.to_sym] || {}
      end

      def summary
        {
          version: rules[:version],
          typography_rules: section(:typography).size,
          layout_rules: section(:layout).size,
          hierarchy_rules: section(:visual_hierarchy).size,
          code_rules: section(:code_craft).size,
        }
      end

      def to_json(*_args)
        JSON.pretty_generate(rules)
      end
    end
  end
end
