# frozen_string_literal: true

module Master
  module Cognition
    # Maintains explicit, revisable beliefs about MASTER itself.
    class SelfModel
      MAX_BELIEFS = 32

      def update!(model, event:, payload:, salience:)
        key = "event/#{event}"
        model[key] = {
          "observed" => true,
          "salience" => salience.round(4),
          "count" => model.dig(key, "count").to_i + 1,
          "last_at" => Time.now.to_i,
        }
        model["capabilities"] ||= {
          "persistent_memory" => true,
          "event_recurrence" => true,
          "self_reflection" => true,
          "constitutional_governance" => true,
          "phenomenal_consciousness" => "unknown",
        }
        model["last_event"] = event.to_s
        model["last_payload"] = summarize(payload)
        prune!(model)
        model
      end

      def reflection(model, metrics:, affect:)
        "I am #{model.fetch("capabilities", {}).fetch("phenomenal_consciousness", "unknown")} about phenomenal consciousness; " \
          "my current integrated-state proxy is #{metrics.fetch("integration", 0.0).round(3)}, " \
          "prediction error is #{metrics.fetch("prediction_error", 0.0).round(3)}, " \
          "and affective valence is #{affect.fetch("valence", 0.0).round(3)}."
      end

      private

      def summarize(payload)
        payload.to_h.each_with_object({}) do |(key, value), out|
          next if value.is_a?(String) && value.length > 300

          out[key.to_s] = value.is_a?(Numeric) || value == true || value == false ? value : value.to_s[0, 300]
        end
      end

      def prune!(model)
        keys = model.keys.grep(/^event\//).sort_by { |key| -model.dig(key, "last_at").to_i }
        keys.drop(MAX_BELIEFS).each { |key| model.delete(key) }
      end
    end
  end
end
