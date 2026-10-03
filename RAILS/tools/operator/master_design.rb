# frozen_string_literal: true

require "yaml"

module Operator
  # RAILS-local reader for MASTER design data. It reads the constitution as data;
  # it does not load MASTER code.
  module MasterDesign
    module_function

    def rules_path
      root = File.expand_path("../../..", __dir__)
      path = File.join(root, "MASTER", "data", "rules.yml")
      File.readable?(path) ? path : nil
    end

    def document(path = rules_path)
      return {} unless path && File.file?(path)

      YAML.safe_load_file(path, aliases: true) || {}
    end

    def blocks(path = rules_path)
      rules = document(path)["rules"]
      Array(rules.is_a?(Hash) ? rules.values.flatten : rules)
        .select { |rule| rule.is_a?(Hash) && rule["tier"] == "design" && rule["config"].is_a?(Hash) }
        .to_h { |rule| [rule["id"].to_s.downcase, rule["config"]] }
    end

    def design_system(path = rules_path) = document(path)["design_system"] || {}

    def dig(*keys, path: rules_path) = blocks(path).dig(*keys.map(&:to_s))
  end
end
