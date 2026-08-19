# frozen_string_literal: true



# ---- merged from lib/fix/homeostat/derived_signals.rb (one-file directory collapse, 2026-08-19) ----
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
# ---- merged from lib/fix/homeostat/health_predicates.rb (one-file directory collapse, 2026-08-19) ----
module Master
  module Fix
    class Homeostat
      # Cognitive health predicates derived from error pressure, fatigue, and
      # energy — separate from Homeostat's own state-decay/event-observation core.
      module HealthPredicates
        def healthy? = !degraded? && !critical?

        def critical?
          t = HEALTH_THRESHOLDS[:critical]
          @state[:error_rate] >= t[:error_rate] ||
            @state[:fatigue] >= t[:fatigue] ||
            @state[:energy] <= t[:energy]
        end

        def degraded?
          return false if critical?
          t = HEALTH_THRESHOLDS[:degraded]
          @state[:error_rate] >= t[:error_rate] ||
            @state[:fatigue] >= t[:fatigue] ||
            @state[:energy] <= t[:energy]
        end

        def health_status
          return :critical if critical?
          return :degraded if degraded?
          :healthy
        end
      end
    end
  end
end

module Master
  module Fix
  # Continuous-time homeostatic drives (CTCS-HRRL, arXiv 2401.08999).
  # State vector decays toward setpoint; events shift it; readers bias routing,
  # reasoning depth, and persona mood. No external deps.
    class Homeostat
      include HealthPredicates
      include DerivedSignals

      DRIVES = {
        energy: { setpoint: 0.7, decay: 0.02 },
        error_rate: { setpoint: 0.0, decay: 0.05 },
        novelty_hunger: { setpoint: 0.5, decay: 0.01 },
        fatigue: { setpoint: 0.0, decay: 0.03 },
        satiety: { setpoint: 0.6, decay: 0.01 },
      }.freeze

      EVENT_DELTAS = {
        llm_call: { energy: -0.05, fatigue: +0.03 },
        llm_success: { error_rate: -0.04, satiety: +0.06, novelty_hunger: -0.02 },
        llm_failure: { error_rate: +0.15, satiety: -0.08, energy: -0.04 },
        tool_call: { fatigue: +0.01 },
        tool_failure: { error_rate: +0.08, fatigue: +0.02 },
        novel_task: { novelty_hunger: -0.20, energy: +0.03 },
        idle_tick: {},
      }.freeze

      # Thresholds for health predicates — cognitive error pressure + exhaustion signal.
      HEALTH_THRESHOLDS = {
        degraded: { error_rate: 0.25, fatigue: 0.6, energy: 0.35 },
        critical: { error_rate: 0.50, fatigue: 0.8, energy: 0.20 },
      }.freeze

      def state = @mutex.synchronize { @state.dup }

      def initialize(event_bus: nil)
        @bus = event_bus
        @mutex = Mutex.new
        @state = DRIVES.transform_values { |spec| spec[:setpoint] }
        @started_at = Time.now
        @prev_health = :healthy
      end

      def observe(event, **_kwargs)
        deltas = EVENT_DELTAS[event] || {}
        snap = @mutex.synchronize do
          deltas.each { |k, v| @state[k] = clamp(@state[k] + v) }
          decay_drift!
          @state.dup
        end
        @bus&.publish("homeostat:observe", event:, state: snap)
        publish_health_transition(snap)
        snap
      end

      def summary
        pairs = @state.map { |k, v| "#{k}=#{format("%.2f", v)}" }.join(" ")
        "homeostat: #{pairs} | mood=#{mood} phase=#{circadian_phase} health=#{health_status}"
      end

      def to_h
        { state: @state.dup, mood:, phase: circadian_phase,
          tier: model_tier_bias, health: health_status }
      end

      private

      def publish_health_transition(_snap)
        current = health_status
        return if current == @prev_health
        @prev_health = current
      end

      def decay_drift!
        DRIVES.each do |drive, spec|
          gap = spec[:setpoint] - @state[drive]
          @state[drive] = clamp(@state[drive] + gap * spec[:decay])
        end
      end

      def clamp(value) = value.clamp(0.0, 1.0)
    end
  end
end
