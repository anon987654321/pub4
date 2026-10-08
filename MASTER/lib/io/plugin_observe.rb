# frozen_string_literal: true

require_relative "../plugin"
require_relative "../result"

module Master
  module Io
    class PluginObserve
      TIER = :guarded
      NAME = "plugin_observe"
      DESCRIPTION = "Observe declared read-only plugin capabilities without granting write authority.".freeze

      def initialize(governor:, event_bus: nil)
        @governor = governor
        @bus = event_bus
      end

      def call(plugin:, action:, args: {})
        payload = args.is_a?(Hash) ? args : nil
        return Result.err("plugin_observe: args must be an object", category: :validation) unless payload

        subject = "#{plugin}:#{action}"
        permitted = @governor.permit?(NAME, TIER, subject)
        return permitted if permitted.err?

        value = Master::Plugin.observe(plugin.to_s, action: action.to_s, **payload)
        @bus&.publish("tool:after", tool: NAME, subject:)
        Result.ok(value)
      rescue Master::Plugin::PolicyError => e
        Result.err(e.message, category: :policy)
      rescue Master::Plugin::ManifestError, Master::Plugin::Error => e
        Result.err(e.message, category: :validation)
      rescue StandardError => e
        Result.err("plugin_observe: #{e.message}", category: :infrastructure)
      end
    end
  end
end
