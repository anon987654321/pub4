# frozen_string_literal: true


module Master
  module Introspection
    class SelfMap
      def initialize(root:)
        @root = root
      end

      def describe
        files = Dir.glob(File.join(@root, "lib/**/*.rb")).sort
        lines = files.sum { |f| File.readlines(f).size }
        mods  = files.map { |f| f.delete_prefix(@root + "/lib/").delete_suffix(".rb").gsub("/", "::") }

        {
          root:   @root,
          files:  files.size,
          lines:,
          modules: mods
        }
      end

      def axiom_coverage
        rules_path = File.join(@root, "data", "rules.yml")
        return {} unless File.exist?(rules_path)

        data = Master.load_yaml(rules_path)
        all_rules = (data["rules"] || {}).values.flatten
        source = Dir.glob(File.join(@root, "lib/**/*.rb")).map { |f| File.read(f) }.join
        all_rules
          .group_by { |r| r["tier"] }
          .transform_values { |rules| rules.count { |r| source.include?(r["id"].to_s) } }
      end
    end
  end
end
