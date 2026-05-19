# frozen_string_literal: true

module Master
  # Unified pressure field model — ingests all bus events, maintains six fields:
  # entropy, confidence, contradiction, turbulence, gravity, scrutiny.
  # Does not mutate runtime behavior; downstream systems read pressure/stability/weather_state.
  class PressureEngine
    DEFAULT_FIELDS = {
      entropy: 0.0,
      confidence: 1.0,
      contradiction: 0.0,
      turbulence: 0.0,
      gravity: 0.0,
      scrutiny: 0.0
    }.freeze

    HISTORY_CAP = 120

    # Pressure formula weights (must sum to 1.0 across all fields)
    PRESSURE_W = {
      entropy: 0.28,
      contradiction: 0.24,
      turbulence: 0.20,
      scrutiny: 0.14,
      confidence_inv: 0.14
    }.freeze
    STABILITY_GRAVITY_W = 0.25
    WEATHER_FRACTURE = 0.85
    WEATHER_STORM    = 0.65
    WEATHER_UNSTABLE = 0.45
    WEATHER_ACTIVE   = 0.25

    # Each rule: [weight, :name|:payload_bool|:payload_float, pattern_or_key]
    # Negative weights subtract. :payload_float multiplies weight by the payload value.
    FIELD_DELTAS = {
      entropy: [
        [+0.18, :name,         /error|failed|rollback|exception/],
        [+0.12, :name,         /contradiction|conflict/],
        [+0.08, :payload_bool, :uncertain],
        [-0.05, :name,         /resolved|stabilized|merged/]
      ],
      confidence: [
        [+0.08, :payload_float, :confidence],
        [-0.12, :name,          /fallback|guess|uncertain/],
        [-0.18, :name,          /contradiction|failed/],
        [+0.06, :name,          /verified|confirmed|tested/]
      ],
      contradiction: [
        [+0.35, :name,         /contradiction|fracture|disagree/],
        [+0.12, :payload_bool, :veto],
        [-0.08, :name,         /consensus|aligned|merged/]
      ],
      turbulence: [
        [+0.18, :name,         /retry|loop|escalat/],
        [+0.10, :payload_bool, :parallel],
        [+0.12, :payload_bool, :recursive],
        [-0.06, :name,         /stable|idle/]
      ],
      gravity: [
        [+0.16, :name,         /memory|retrieve|reference|evidence/],
        [+0.08, :payload_bool, :citations],
        [-0.04, :name,         /drift|fragment/]
      ],
      scrutiny: [
        [+0.16, :name,         /judge|scrutiny|epistemic|verify/],
        [+0.10, :payload_bool, :critique],
        [-0.05, :name,         /blind|unchecked/]
      ]
    }.freeze

    attr_reader :fields

    def initialize(event_bus: nil)
      @bus     = event_bus
      @fields  = DEFAULT_FIELDS.dup
      @history = []
    end

    def ingest(event:, payload: {})
      name = event.to_s
      apply_all(name, payload)
      normalize!
      snapshot(name)
      emit(name)
      fields.dup
    end

    def pressure
      (fields[:entropy]       * PRESSURE_W[:entropy] +
       fields[:contradiction] * PRESSURE_W[:contradiction] +
       fields[:turbulence]    * PRESSURE_W[:turbulence] +
       fields[:scrutiny]      * PRESSURE_W[:scrutiny] +
       (1.0 - fields[:confidence]) * PRESSURE_W[:confidence_inv]).clamp(0.0, 1.0)
    end

    def stability = (1.0 - pressure + fields[:gravity] * STABILITY_GRAVITY_W).clamp(0.0, 1.0)

    def weather_state
      return :fracture if pressure >= WEATHER_FRACTURE
      return :storm    if pressure >= WEATHER_STORM
      return :unstable if pressure >= WEATHER_UNSTABLE
      return :active   if pressure >= WEATHER_ACTIVE
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

    def apply_all(name, payload)
      FIELD_DELTAS.each do |field, rules|
        d = rules.sum do |weight, source, matcher|
          case source
          when :name         then name.match?(matcher) ? weight : 0.0
          when :payload_bool then payload[matcher] ? weight : 0.0
          when :payload_float then payload.key?(matcher) ? payload[matcher].to_f * weight : 0.0
          else 0.0
          end
        end
        @fields[field] += d
      end
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
