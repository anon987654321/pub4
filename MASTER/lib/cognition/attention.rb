# frozen_string_literal: true

module Master
  module Cognition
    # Lightweight salience model inspired by global-workspace architectures.
    # It chooses what deserves scarce internal attention; it does not claim to
    # reproduce biological attention.
    class Attention
      EVENT_WEIGHTS = {
        "tool:after" => 0.65,
        "tool:error" => 0.9,
        "chat:message" => 0.8,
        "error" => 0.95,
        "warning" => 0.7,
        "standing_order:ran" => 0.35,
        "pressure:changed" => 0.45,
      }.freeze

      def score(event:, payload:, prediction_error:, affect:)
        base = EVENT_WEIGHTS.fetch(event.to_s, 0.25)
        novelty = prediction_error.to_f.clamp(0.0, 1.0)
        arousal = affect.fetch("arousal", 0.25).to_f.clamp(0.0, 1.0)
        urgency = payload_value(payload, :severity).to_s == "critical" ? 0.35 : 0.0
        (base * 0.55 + novelty * 0.3 + arousal * 0.15 + urgency).clamp(0.0, 1.0)
      end

      private

      def payload_value(payload, key)
        payload[key] || payload[key.to_s]
      end
    end
  end
end
