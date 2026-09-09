# frozen_string_literal: true

module Master
  module Cognition
    # What deserves scarce internal attention, scored from the event, how novel
    # it is, and how aroused the affect model already is. A salience heuristic
    # borrowed from global-workspace architectures, not a claim to reproduce
    # biological attention.
    class Attention
      EVENT_WEIGHTS = {
        "error:swallowed" => 0.95,
        "tool:error" => 0.9,
        "chat:message" => 0.8,
        "scan:complete" => 0.7,
        "tool:after" => 0.65,
        "pressure:changed" => 0.45,
        "standing_order:ran" => 0.35,
      }.freeze

      DEFAULT_WEIGHT = 0.25

      def score(event:, payload:, prediction_error:, affect:)
        base = EVENT_WEIGHTS.fetch(event.to_s, DEFAULT_WEIGHT)
        novelty = prediction_error.to_f.clamp(0.0, 1.0)
        arousal = affect.fetch("arousal", 0.25).to_f.clamp(0.0, 1.0)
        (base * 0.55 + novelty * 0.3 + arousal * 0.15 + urgency(payload)).clamp(0.0, 1.0)
      end

      private

      # The bus merges symbol keys into every payload, so a symbol lookup is the
      # only one that can hit.
      def urgency(payload)
        payload.is_a?(Hash) && payload[:severity].to_s == "critical" ? 0.35 : 0.0
      end
    end
  end
end
