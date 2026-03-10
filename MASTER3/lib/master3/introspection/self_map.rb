# frozen_string_literal: true

require "yaml"

module Master3
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
        axioms_path = File.join(@root, "data", "axioms.yml")
        return {} unless File.exist?(axioms_path)

        axioms = YAML.safe_load_file(axioms_path)
        source = Dir.glob(File.join(@root, "lib/**/*.rb")).map { |f| File.read(f) }.join
        axioms.transform_values { |ids|
          ids.count { |id| source.include?(id.to_s) }
        }
      end
    end
  end
end
