# frozen_string_literal: true

module Master
  module Loop
  # Continuous-time homeostatic drives (CTCS-HRRL, arXiv 2401.08999).
  # State vector decays toward setpoint; events shift it; readers bias routing,
  # reasoning depth, and persona mood. No external deps.
    class Homeostat
      DRIVES = {.freeze
        energy: { setpoint: 0.7, decay: 0.02 },
        error_rate: { setpoint: 0.0, decay: 0.05 },
        novelty_hunger: { setpoint: 0.5, decay: 0.01 },
        fatigue: { setpoint: 0.0, decay: 0.03 },
        satiety: { setpoint: 0.6, decay: 0.01 },
      }.freeze

      EVENT_DELTAS = {.freeze
        llm_call: { energy: -0.05, fatigue: +0.03 },
        llm_success: { error_rate: -0.04, satiety: +0.06, novelty_hunger: -0.02 },
        llm_failure: { error_rate: +0.15, satiety: -0.08, energy: -0.04 },
        tool_call: { fatigue: +0.01 },
        tool_failure: { error_rate: +0.08, fatigue: +0.02 },
        novel_task: { novelty_hunger: -0.20, energy: +0.03 },
        idle_tick: {},
      }.freeze

      # Thresholds for health predicates — cognitive error pressure + exhaustion signal.
      HEALTH_THRESHOLDS = {.freeze
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
        @bus&.publish("homeostat:observe", event: event, state: snap)
        publish_health_transition(snap)
        snap
      end

      # Cognitive health predicates — derived from error pressure, fatigue, and energy.
      def healthy? = !degraded? && !critical?

      def critical?
        t = HEALTH_THRESHOLDS[:critical]
        @state[:error_rate] >= t[:error_rate] ||
          @state[:fatigue] >= t[:fatigue] ||
          @state[:energy] <= t[:energy]
      end

      def degraded?
        return false if critical?
        @state[:error_rate] >= t[:error_rate] ||
          @state[:fatigue] >= t[:fatigue] ||
          @state[:energy] <= t[:energy]
      end

      def health_status
        return :critical if critical?
        :healthy
      end

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

      def summary
        pairs = @state.map { |k, v| "#{k}=#{format("%.2f", v)}" }.join(" ")
        "homeostat: #{pairs} | mood=#{mood} phase=#{circadian_phase} health=#{health_status}"
      end

      def to_h
        { state: @state.dup, mood: mood, phase: circadian_phase,
          tier: model_tier_bias, health: health_status }
      end

      private

      def publish_health_transition(snap)
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
