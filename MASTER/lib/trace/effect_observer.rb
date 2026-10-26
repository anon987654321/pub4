# frozen_string_literal: true

require "securerandom"
require_relative "../execution/contract"

module Master
  module Trace
    # Bridges the Fold's effect lifecycle to the event bus's strict persistence
    # API. The Fold does not depend on Trace; hosts inject this callable adapter.
    class EffectObserver
      BEFORE_EVENT = "core:effect:before"
      AFTER_EVENT = "core:effect:after"

      def initialize(bus:, run_id: SecureRandom.uuid, attempt_id: nil, mission_id: nil)
        raise ArgumentError, "effect audit requires publish_required" unless bus.respond_to?(:publish_required)

        @bus = bus
        @run_id = Master::Execution::Contract.token!(run_id, "run id")
        @attempt_id = Master::Execution::Contract.token!(attempt_id, "attempt id") if attempt_id
        @mission_id = Master::Execution::Contract.token!(mission_id, "mission id") if mission_id
      end

      def call(stage:, turn:, effect:, effect_id:, operation: :perform, parent_effect_id: nil,
               checkpoint_id: nil, run_id: nil, attempt_id: nil, mission_id: nil, scope: nil,
               idempotency_key: nil, deadline_at: nil, reversibility: :unknown, evidence_refs: [],
               observation: nil, elapsed_ms: nil)
        payload = Master::Execution::Contract::EffectEnvelope.build(
          effect:, turn:, effect_id:, operation:, parent_effect_id:, checkpoint_id:,
          run_id: run_id || @run_id, attempt_id: attempt_id || @attempt_id,
          mission_id: mission_id || @mission_id, scope:,
          idempotency_key:, deadline_at:, reversibility:
        ).to_h
        references = safe_evidence_refs(evidence_refs)
        payload[:evidence_refs] = references unless references.empty?

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

      def safe_evidence_refs(references)
        Array(references).map do |reference|
          unless reference.is_a?(Master::Execution::Contract::EvidenceReference)
            raise ArgumentError, "evidence refs must use the typed EvidenceReference contract"
          end

          reference.to_h
        end
      end

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
