# frozen_string_literal: true

module Master
  # PressureEngine unifies governance, epistemics, repo ecology,
  # and cognition telemetry into one executable field model.
  #
  # The engine does not mutate runtime behavior directly.
  # It computes pressure states that downstream systems may consume:
  # - governance
  # - cognition map
  # - repo ecology
  # - orchestration
  # - escalation
  # - telemetry
  class PressureEngine
    DEFAULT_FIELDS = {
      entropy: 0.0,
      confidence: 1.0,
      contradiction: 0.0,
      turbulence: 0.0,
      gravity: 0.0,
      scrutiny: 0.0
    }.freeze

    attr_reader :fields

    def initialize(event_bus: nil)
      @bus = event_bus
      @fields = DEFAULT_FIELDS.dup
      @history = []
    end

    def ingest(event:, payload: {})
      name = event.to_s

      apply_entropy(name, payload)
      apply_confidence(name, payload)
      apply_contradiction(name, payload)
      apply_turbulence(name, payload)
      apply_gravity(name, payload)
      apply_scrutiny(name, payload)

      normalize!
      snapshot(name)

      emit(name)

      fields.dup
    end

    def pressure
      (
        fields[:entropy] * 0.28 +
        fields[:contradiction] * 0.24 +
        fields[:turbulence] * 0.20 +
        fields[:scrutiny] * 0.14 +
        (1.0 - fields[:confidence]) * 0.14
      ).clamp(0.0, 1.0)
    end

    def stability
      (1.0 - pressure + fields[:gravity] * 0.25).clamp(0.0, 1.0)
    end

    def weather_state
      return :fracture if pressure >= 0.85
      return :storm if pressure >= 0.65
      return :unstable if pressure >= 0.45
      return :active if pressure >= 0.25

      :calm
    end

    def snapshot(label = nil)
      point = {
        label:,
        pressure: pressure.round(4),
        stability: stability.round(4),
        weather: weather_state,
        fields: fields.transform_values { |v| v.round(4) },
        at: Time.now.utc.iso8601
      }

      @history << point
      @history.shift while @history.size > 120

      point
    end

    def history
      @history.dup
    end

    private

    def apply_entropy(name, payload)
      delta = 0.0
      delta += 0.18 if name.match?(/error|failed|rollback|exception/)
      delta += 0.12 if name.match?(/contradiction|conflict/)
      delta += 0.08 if payload[:uncertain]
      delta -= 0.05 if name.match?(/resolved|stabilized|merged/)

      fields[:entropy] += delta
    end

    def apply_confidence(name, payload)
      delta = 0.0
      delta += payload[:confidence].to_f * 0.08 if payload.key?(:confidence)
      delta -= 0.12 if name.match?(/fallback|guess|uncertain/)
      delta -= 0.18 if name.match?(/contradiction|failed/)
      delta += 0.06 if name.match?(/verified|confirmed|tested/)

      fields[:confidence] += delta
    end

    def apply_contradiction(name, payload)
      delta = 0.0
      delta += 0.35 if name.match?(/contradiction|fracture|disagree/)
      delta += 0.12 if payload[:veto]
      delta -= 0.08 if name.match?(/consensus|aligned|merged/)

      fields[:contradiction] += delta
    end

    def apply_turbulence(name, payload)
      delta = 0.0
      delta += 0.18 if name.match?(/retry|loop|escalat/)
      delta += 0.10 if payload[:parallel]
      delta += 0.12 if payload[:recursive]
      delta -= 0.06 if name.match?(/stable|idle/)

      fields[:turbulence] += delta
    end

    def apply_gravity(name, payload)
      delta = 0.0
      delta += 0.16 if name.match?(/memory|retrieve|reference|evidence/)
      delta += 0.08 if payload[:citations]
      delta -= 0.04 if name.match?(/drift|fragment/)

      fields[:gravity] += delta
    end

    def apply_scrutiny(name, payload)
      delta = 0.0
      delta += 0.16 if name.match?(/judge|scrutiny|epistemic|verify/)
      delta += 0.10 if payload[:critique]
      delta -= 0.05 if name.match?(/blind|unchecked/)

      fields[:scrutiny] += delta
    end

    def normalize!
      fields.each_key do |key|
        fields[key] = fields[key].clamp(0.0, 1.0)
      end
    end

    def emit(label)
      @bus&.publish(
        "pressure:updated",
        label:,
        pressure: pressure,
        stability: stability,
        weather: weather_state,
        fields: fields.dup
      )
    end
  end
end
