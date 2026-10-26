# frozen_string_literal: true

module Master
  module Trace
    # Bridges the Fold's effect lifecycle to the event bus's strict persistence
    # API. The Fold does not depend on Trace; hosts inject this callable adapter.
    class EffectObserver
      BEFORE_EVENT = "core:effect:before"
      AFTER_EVENT = "core:effect:after"

      def initialize(bus:)
        raise ArgumentError, "effect audit requires publish_required" unless bus.respond_to?(:publish_required)

        @bus = bus
      end

      def call(stage:, turn:, effect:, effect_id:, operation: :perform, parent_effect_id: nil,
               checkpoint_id: nil, observation: nil, elapsed_ms: nil)
        payload = { effect_id:, turn:, verb: effect.verb, capability: effect.capability, operation: }
        payload[:parent_effect_id] = parent_effect_id if parent_effect_id
        payload[:checkpoint_id] = checkpoint_id if checkpoint_id

        case stage.to_sym
        when :before
          @bus.publish_required(BEFORE_EVENT, payload)
        when :after
          publish_after(payload, observation, elapsed_ms)
        else
          raise ArgumentError, "unknown effect lifecycle stage: #{stage}"
        end
      end

      private

      def publish_after(payload, observation, elapsed_ms)
        raise ArgumentError, "after-event requires an observation" unless observation

        @bus.publish_required(
          AFTER_EVENT,
          payload.merge(status: observation.ok? ? "ok" : "error", elapsed_ms:)
        )
      end
    end
  end
end
