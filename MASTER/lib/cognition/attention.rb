# frozen_string_literal: true

module Master
  module Cognition
    # What deserves scarce internal attention, scored from the event, how novel
    # it is, and how aroused the affect model already is. A salience heuristic
    # borrowed from global-workspace architectures, not a claim to reproduce
    # biological attention.
    #
    # Every row names an event something in the tree publishes. A weight for an
    # event nobody publishes is a salience the layer never computes, so a new
    # row lands with its publisher.
    #
    # CLI::AttentionContext shares the word and not the job: it renders the
    # map/zoom/act breadcrumb into the prompt and carries no weights.
    class Attention
      EVENT_WEIGHTS = {
        "error:swallowed" => 0.95,
        "scan:complete" => 0.7,
        "tool:after" => 0.65,
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
