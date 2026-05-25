# frozen_string_literal: true

require "yaml"
require_relative "../master_paths"

module Harness
  class Registry
    def initialize(dir: MasterPaths.data("harnesses"))
      @dir = dir
    end

    def all
      Dir.glob(File.join(@dir, "*.yml")).to_h do |path|
        [File.basename(path, ".yml"), YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: true)]
      end
    end

    def fetch(name)
      all.fetch(name.to_s)
    end

    def coverage_for(path)
      all.select do |_name, spec|
        Array(spec["paths"]).any? { |prefix| path.start_with?(prefix) }
      end
    end

    def missing_for(paths)
      Array(paths).select { |path| coverage_for(path).empty? }
    end
  end
end
