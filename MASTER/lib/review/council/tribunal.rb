# frozen_string_literal: true

require_relative "evidence"
require_relative "deliberation"
require_relative "voice_profile"

module Master
  module Review
    module Council
      # Evidence-first orchestration shared by UI, sound, Dilla, /fix and
      # future information-flow, 3D, particle, face and body probes.
      class Tribunal
        def initialize(agent:, event_bus: nil, judge_enabled: true, speak_personas: false)
          @agent = agent
          @bus = event_bus
          @judge_enabled = judge_enabled
          @speak_personas = speak_personas
        end

        def review(evidence:, personas:, context:, image: nil)
          bundle = normalize(evidence)
          return inconclusive(bundle, "no evidence") if bundle.empty?

          if bundle.none?(&:actionable?) && bundle.all?(&:inconclusive?)
            return inconclusive(bundle, "all probes are inconclusive")
          end

          payload = bundle.map(&:prompt).join("\n\n")
          @bus&.publish(:tribunal_observed, evidence: bundle.map(&:to_h))

          result = Deliberation.new(
            personas:,
            agent: @agent,
            event_bus: @bus,
            judge_enabled: @judge_enabled,
            voice_personas: @speak_personas,
          ).review(payload, context:, image:)

          return result unless result.ok?

          value = result.value!
          @bus&.publish(
            :tribunal_synthesized,
            evidence_count: bundle.size,
            actionable_count: bundle.count(&:actionable?),
            feedback_count: Array(value).size,
            voice_personas: @speak_personas,
          )
          result
        end

        private

        def normalize(value)
          Array(value).filter_map do |item|
            case item
            when Evidence then item
            when Hash then Evidence.new(**symbolize(item))
            end
          end
        end

        def symbolize(hash)
          hash.each_with_object({}) { |(key, value), result| result[key.to_sym] = value }
        end

        def inconclusive(bundle, reason)
          Master::Result.ok({
            status: :inconclusive,
            reason:,
            evidence: bundle.map(&:to_h),
            feedback: [],
          })
        end
      end
    end
  end
end
