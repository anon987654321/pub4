# frozen_string_literal: true

require "yaml"

module Master
  module Backlog
    class Registry
      REGISTRY_PATH = File.join(Master::ROOT, "data", "todo_artifacts.yml").freeze

      @items = {}
      @loaded = false

      class << self
        def load!
          return @items if @loaded

          data = if File.exist?(REGISTRY_PATH)
                   YAML.safe_load(File.read(REGISTRY_PATH), permitted_classes: [Symbol], aliases: true) || {}
                 else
                   {}
                 end
          @items = data.transform_keys(&:to_s)
          @loaded = true
          @items
        end

        def register(id, handler = nil)
          load!
          @items[id.to_s] ||= { "id" => id.to_s, "implemented" => true }
          @items[id.to_s]["handler"] = handler if handler
          true
        end

        def implemented?(id)
          entry = load![id.to_s]
          return false unless entry

          path = File.join(Master::ROOT, entry["artifact"].to_s)
          File.exist?(path)
        end

        def wire_all!(container = nil)
          load!
          Master::Backlog::Engines.wire_all! if defined?(Master::Backlog::Engines)
          container
        end

        def count
          load!.size
        end
      end
    end
  end
end
