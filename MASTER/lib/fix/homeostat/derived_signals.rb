# frozen_string_literal: true

module Master
  module Fix
    class Homeostat
      # Persona/routing signals derived from drive state — mood, circadian
      # phase, model-tier bias — separate from the core drive-decay state.
      module DerivedSignals
        def model_tier_bias
          return :cheap if @state[:error_rate] > 0.4 || @state[:fatigue] > 0.7
          :default
        end

        # Personality::MOOD_LINES declares four moods and this returned two of
        # them plus nil. :weary and :focused had never been emitted, and the nil
        # was worse than the gap: PersonalityPromptBuilder does
        # `MOOD_LINES[@homeostat.mood]` and joins the result, so a calm,
        # incurious state put a blank line inside <master_runtime_state> where
        # the mood belonged. Nothing raised and nothing logged.
        #
        # Order is by urgency, not by drive: an elevated error rate outranks
        # fatigue, and both outrank curiosity. :focused is the setpoint state and
        # therefore the default -- MOOD_LINES already words it that way ("drives
        # at setpoint"), which is the clearest evidence it was meant to be
        # reachable.
        #
        # The fatigue edge is HEALTH_THRESHOLDS[:degraded][:fatigue], not a
        # second number: "weary" and "degraded by fatigue" are the same claim,
        # and two constants for one idea drift.
        def mood
          return :tense if @state[:error_rate] > 0.4
          return :weary if @state[:fatigue] >= Homeostat::HEALTH_THRESHOLDS[:degraded][:fatigue]
          return :curious if @state[:novelty_hunger] > 0.6

          :focused
        end

        # Same shape, same fix. PHASE_LINES declares morning/afternoon/evening/
        # night; this returned morning, evening and nil, so the twelve hours from
        # noon and the six from eleven at night resolved to no phase line at all.
        #
        # The bands are contiguous and total: every hour of the day belongs to
        # exactly one. Night wraps midnight, which is why it is the fallback
        # rather than a range -- `(23..4)` covers nothing.
        def circadian_phase
          h = Time.now.hour
          return :morning if (5..11).cover?(h)
          return :afternoon if (12..17).cover?(h)
          return :evening if (18..22).cover?(h)

          :night
        end
      end
    end
  end
end
