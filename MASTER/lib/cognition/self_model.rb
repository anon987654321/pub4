# frozen_string_literal: true

module Master
  module Cognition
    # Explicit, revisable beliefs about MASTER itself.
    #
    # `phenomenal_consciousness` is "unknown" and stays that way. It is a
    # capability entry rather than a comment because soul.yml's anti_simulation
    # section forbids claiming what has not been shown, and the honest answer to
    # this one cannot be reached by running more code.
    class SelfModel
      MAX_BELIEFS = 32

      CAPABILITIES = {
        "persistent_memory" => true,
        "event_recurrence" => true,
        "self_reflection" => true,
        "constitutional_governance" => true,
        "phenomenal_consciousness" => "unknown",
      }.freeze

      def update!(model, event:, payload:, salience:)
        key = "event/#{event}"
        model[key] = {
          "salience" => salience.round(4),
          "count" => model.dig(key, "count").to_i + 1,
          "last_at" => Time.now.to_i,
        }
        model["capabilities"] ||= CAPABILITIES.dup
        model["last_event"] = event.to_s
        model["last_payload"] = summarize(payload)
        prune!(model)
        model
      end

      def reflection(model, metrics:, affect:)
        stance = model.fetch("capabilities", CAPABILITIES).fetch("phenomenal_consciousness", "unknown")
        "I am #{stance} about phenomenal consciousness; my integrated-state proxy is " \
          "#{metrics.fetch("integration", 0.0).round(3)}, prediction error " \
          "#{metrics.fetch("prediction_error", 0.0).round(3)}, valence " \
          "#{affect.fetch("valence", 0.0).round(3)}."
      end

      private

      def summarize(payload)
        return {} unless payload.is_a?(Hash)

        payload.each_with_object({}) do |(key, value), out|
          out[key.to_s] = value.is_a?(Numeric) || value == true || value == false ? value : value.to_s[0, 200]
        end
      end

      def prune!(model)
        beliefs = model.keys.grep(%r{\Aevent/}).sort_by { |key| -model.dig(key, "last_at").to_i }
        beliefs.drop(MAX_BELIEFS).each { |key| model.delete(key) }
      end
    end
  end
end
