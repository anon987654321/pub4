# frozen_string_literal: true

module Master
  module Io
    # Runtime HTTP tool registry (OpenCrabs tools.toml parity) — data-driven endpoints
    # without redeploying Ruby adapters.
    module DynamicTools
      PATHS = [
        File.join(Master::ROOT, "data", "tools.dynamic.yml"),
        File.expand_path("~/.master/tools.dynamic.yml"),
      ].freeze

      module_function

      def load_definitions
        PATHS.flat_map { |path| load_path(path) }.uniq { |row| row["name"].to_s }
      end

      def load_path(path)
        return [] unless File.file?(path)

        rows = Master.load_yaml(path)
        return [] unless rows.is_a?(Array)

        rows.select { |row| row.is_a?(Hash) && row["enabled"] != false && !row["name"].to_s.empty? }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "dynamic_tools.load", path:)
        []
      end

      # Per row, at call time. Every row reaches a model through the one
      # DynamicHttp tool, whose single registry entry cannot carry a different
      # exposure per row. An HTTP endpoint reaches the open world, so a row that
      # does not declare itself unelevated waits for elevation.
      def elevated?(row) = row["elevated"] != false

      def lookup(name)
        load_definitions.find { |row| row["name"].to_s == name.to_s }
      end
    end
  end
end
