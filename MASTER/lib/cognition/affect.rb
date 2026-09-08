# frozen_string_literal: true

module Master
  module Cognition
    # Homeostatic affect model. Values are deliberately bounded and inspectable.
    class Affect
      def update!(affect, prediction_error:, salience:, success: nil)
        error = prediction_error.to_f.clamp(0.0, 1.0)
        salience = salience.to_f.clamp(0.0, 1.0)
        valence = affect.fetch("valence", 0.0).to_f
        arousal = affect.fetch("arousal", 0.25).to_f

        delta = if success == true
          0.08
        elsif success == false
          -0.12
        else
          (0.5 - error) * 0.03
        end

        affect["valence"] = (valence + delta).clamp(-1.0, 1.0)
        affect["arousal"] = (arousal * 0.82 + (error * 0.65 + salience * 0.35) * 0.18).clamp(0.0, 1.0)
        affect["novelty"] = error
        affect["uncertainty"] = (affect.fetch("uncertainty", 0.5).to_f * 0.9 + error * 0.1).clamp(0.0, 1.0)
        affect
      end
    end
  end
end
