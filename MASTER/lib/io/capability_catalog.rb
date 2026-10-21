# frozen_string_literal: true

require_relative "../ground/capability_catalog"
require_relative "../result"

module Master
  module Io
    # Read-only inventory of registered built-in tools and plugin observation
    # actions. Discovery does not load or execute a plugin.
    class CapabilityCatalog
      TIER = :guarded
      NAME = "capability_catalog"
      DESCRIPTION = "Discover registered core tools and declared read-only plugin capabilities.".freeze

      def initialize(root: Master::ROOT, governor:, event_bus: nil)
        @root = root
        @governor = governor
        @bus = event_bus
      end

      def call(action:, query: nil, name: nil)
        verb = action.to_s
        permitted = @governor.permit?(NAME, TIER, verb)
        return permitted if permitted.err?

        result = Ground::CapabilityCatalog.call(action: verb, query:, name:, root: @root)
        if result["status"] == "inconclusive"
          return Result.err(result["reason"], category: :infrastructure)
        end

        @bus&.publish("tool:after", tool: NAME, action: verb)
        Result.ok(result)
      rescue ArgumentError => e
        Result.err("capability_catalog: #{e.message}", category: :validation)
      rescue StandardError => e
        Result.err("capability_catalog: #{e.class}: #{e.message}", category: :infrastructure)
      end
    end
  end
end
