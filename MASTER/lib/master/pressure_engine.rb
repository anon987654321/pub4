# frozen_string_literal: true

module Master
  # Unified pressure field model — ingests all bus events, maintains six fields:
  # entropy, confidence, contradiction, turbulence, gravity, scrutiny.
  # Does not mutate runtime behavior; downstream systems read pressure/stability/weather_state.
  class PressureEngine
    DEFAULT_FIELDS = {
      entropy:       0.0,
      confidence:    1.0,
      contradiction: 0.0,
      turbulence:    0.0,
      gravity:       0.0,
      scrutiny:      0.0
    }.freeze

    HISTORY_CAP = 120

    attr_reader :fields

    def initialize(event_bus: nil)
      @bus     = event_bus
      @fields  = DEFAULT_FIELDS.dup
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
      (fields[:entropy]       * 0.28 +
       fields[:contradiction] * 0.24 +
       fields[:turbulence]    * 0.20 +
       fields[:scrutiny]      * 0.14 +
       (1.0 - fields[:confidence]) * 0.14).clamp(0.0, 1.0)
    end

    def stability = (1.0 - pressure + fields[:gravity] * 0.25).clamp(0.0, 1.0)

    def weather_state
      return :fracture if pressure >= 0.85
      return :storm    if pressure >= 0.65
      return :unstable if pressure >= 0.45
      return :active   if pressure >= 0.25
      :calm
    end

    def snapshot(label = nil)
      point = { label:, pressure: pressure.round(4), stability: stability.round(4),
                weather: weather_state, fields: fields.transform_values { |v| v.round(4) },
                at: Time.now.utc.iso8601 }
      @history << point
      @history.shift while @history.size > HISTORY_CAP
      point
    end

    def history = @history.dup

    private

    def apply_entropy(name, payload)
      d  = 0.0
      d += 0.18 if name.match?(/error|failed|rollback|exception/)
      d += 0.12 if name.match?(/contradiction|conflict/)
      d += 0.08 if payload[:uncertain]
      d -= 0.05 if name.match?(/resolved|stabilized|merged/)
      fields[:entropy] += d
    end

    def apply_confidence(name, payload)
      d  = 0.0
      d += payload[:confidence].to_f * 0.08 if payload.key?(:confidence)
      d -= 0.12 if name.match?(/fallback|guess|uncertain/)
      d -= 0.18 if name.match?(/contradiction|failed/)
      d += 0.06 if name.match?(/verified|confirmed|tested/)
      fields[:confidence] += d
    end

    def apply_contradiction(name, payload)
      d  = 0.0
      d += 0.35 if name.match?(/contradiction|fracture|disagree/)
      d += 0.12 if payload[:veto]
      d -= 0.08 if name.match?(/consensus|aligned|merged/)
      fields[:contradiction] += d
    end

    def apply_turbulence(name, payload)
      d  = 0.0
      d += 0.18 if name.match?(/retry|loop|escalat/)
      d += 0.10 if payload[:parallel]
      d += 0.12 if payload[:recursive]
      d -= 0.06 if name.match?(/stable|idle/)
      fields[:turbulence] += d
    end

    def apply_gravity(name, payload)
      d  = 0.0
      d += 0.16 if name.match?(/memory|retrieve|reference|evidence/)
      d += 0.08 if payload[:citations]
      d -= 0.04 if name.match?(/drift|fragment/)
      fields[:gravity] += d
    end

    def apply_scrutiny(name, payload)
      d  = 0.0
      d += 0.16 if name.match?(/judge|scrutiny|epistemic|verify/)
      d += 0.10 if payload[:critique]
      d -= 0.05 if name.match?(/blind|unchecked/)
      fields[:scrutiny] += d
    end

    def normalize!
      fields.each_key { |k| fields[k] = fields[k].clamp(0.0, 1.0) }
    end

    def emit(label)
      @bus&.publish("pressure:updated",
                    label:, pressure:, stability:, weather: weather_state, fields: fields.dup)
    end
  end
end
