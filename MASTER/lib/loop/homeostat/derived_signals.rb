# frozen_string_literal: true

module Master
  module Loop
    class Homeostat
      # Persona/routing signals derived from drive state — mood, circadian
      # phase, model-tier bias — separate from the core drive-decay state.
      module DerivedSignals
        def model_tier_bias
          return :cheap if @state[:error_rate] > 0.4 || @state[:fatigue] > 0.7
          :default
        end

        def mood
          return :tense if @state[:error_rate] > 0.4
          return :curious if @state[:novelty_hunger] > 0.6
        end

        def circadian_phase
          h = Time.now.hour
          return :morning if (5..11).cover?(h)
          return :evening if (18..22).cover?(h)
        end
      end
    end
  end
end
