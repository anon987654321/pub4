# frozen_string_literal: true

module Master
  module Cognition
    # A homeostatic affect model. Every value is bounded and inspectable on
    # purpose: an unbounded mood accumulates and then explains everything.
    class Affect
      SUCCESS_DELTA = 0.08
      FAILURE_DELTA = -0.12

      def update!(affect, prediction_error:, salience:, success: nil)
        error = prediction_error.to_f.clamp(0.0, 1.0)
        salience = salience.to_f.clamp(0.0, 1.0)

        affect["valence"] = (affect.fetch("valence", 0.0).to_f + valence_delta(success, error)).clamp(-1.0, 1.0)
        affect["arousal"] = arousal(affect, error, salience)
        affect["novelty"] = error
        affect["uncertainty"] = (affect.fetch("uncertainty", 0.5).to_f * 0.9 + error * 0.1).clamp(0.0, 1.0)
        affect
      end

      private

      # An outcome moves valence; without one, a surprise nudges it down and a
      # confirmed expectation nudges it up, which is the whole of the mood.
      def valence_delta(success, error)
        case success
        when true then SUCCESS_DELTA
        when false then FAILURE_DELTA
        else (0.5 - error) * 0.03
        end
      end

      # Leaky: 82% of the previous reading survives, so arousal falls back to
      # rest on its own rather than needing something calm to push it down.
      def arousal(affect, error, salience)
        previous = affect.fetch("arousal", 0.25).to_f
        (previous * 0.82 + (error * 0.65 + salience * 0.35) * 0.18).clamp(0.0, 1.0)
      end
    end
  end
end
