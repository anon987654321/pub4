# frozen_string_literal: true

module Master
  module Voice
    # Ruby-side visual runtime helpers: micro-interaction bus events,
    # vertical timbre bias, and felt-sense aggregation for round-trip context.
    module VisualRuntime
      MICRO_BUS_MAP = {
        "mi_009" => { event: "master:visual", mode: "input:paste", entropy: 0.25 },
        "mi_042" => { event: "master:visual", mode: "user:interrupt", entropy: 0.4 },
        "mi_048" => { event: "master:visual", mode: "cmd:long", entropy: 0.35, confidence: 0.72 },
        "mi_050" => { event: "master:visual", mode: "link:thinking", entropy: 0.42, confidence: 0.55 },
        "mi_035" => { event: "master:visual", mode: "link:quiet", entropy: 0.38, confidence: 0.65 },
        "mi_064" => {
          event: "council:deliberation", mode: "start", entropy: 0.45, confidence: 0.58,
          spirit_radius: Expression.council_spirit_radius(risk: :medium, reversibility: :low)
        },
        "mi_062" => { event: "tts:style:active", mode: "style", entropy: 0.22, confidence: 0.80 },
        "user_interrupt" => { event: "master:visual", mode: "user:interrupt", entropy: 0.4 },
        "input_paste" => { event: "master:visual", mode: "input:paste", entropy: 0.25 },
        "input_long" => { event: "master:visual", mode: "input:long", entropy: 0.30, confidence: 0.70 },
        "link_quiet" => { event: "master:visual", mode: "link:quiet", entropy: 0.38, confidence: 0.65 },
        "link_thinking" => { event: "master:visual", mode: "link:thinking", entropy: 0.42, confidence: 0.55 },
        "council_deliberation" => {
          event: "council:deliberation", mode: "start", entropy: 0.45, confidence: 0.58,
          spirit_radius: Expression.council_spirit_radius(risk: :medium, reversibility: :low)
        },
        "tts_style_active" => { event: "tts:style:active", mode: "style", entropy: 0.22, confidence: 0.80 },
      }.freeze

      DEFAULT_VERTICAL_BIAS = { arousal: 0.5, valence: 0.1, focus: 0.6, terrain: "neutral" }.freeze

      module_function

      def apply_micro_interaction(id, bus:, ctx: {})
        spec = resolve_micro_spec(id)
        return false unless spec && bus

        payload = spec.except(:event, "event").merge(ctx.is_a?(Hash) ? ctx : {})
        event = spec[:event] || spec["event"] || "master:visual"
        bus.publish(event, payload.transform_keys(&:to_sym))
        true
      rescue StandardError => e
        Ground::Swallow.log(e, context: "VisualRuntime.apply_micro_interaction", id: id.to_s)
        false
      end

      def vertical_timbre(app:)
        key = app.to_s.downcase.strip
        return DEFAULT_VERTICAL_BIAS if key.empty?

        timbre = Ground::RuntimeCatalog.ui_philosophy.dig("vertical_timbre", key)
        return DEFAULT_VERTICAL_BIAS unless timbre.is_a?(Hash) && timbre.any?

        DEFAULT_VERTICAL_BIAS.merge(timbre.transform_keys(&:to_sym))
      end

      def felt_sense_snapshot(session: nil, state: nil)
        base = normalize_felt_state(state)
        history = felt_history_from_session(session)
        fused_confidence = Expression.fuse_confidence(
          verdict: base[:confidence],
          retrieval: history.dig(:retrieval, :score),
          council: history.dig(:council, :score)
        )

        {
          mood: base[:mood],
          mode: base[:mode],
          entropy: base[:entropy],
          confidence: fused_confidence,
          arousal: base[:arousal],
          valence: base[:valence],
          vertical: base[:vertical],
          turn_count: history[:turn_count],
          recent_entropy_avg: history[:recent_entropy_avg],
        }
      end

      def resolve_micro_spec(id)
        entry = Ground::RuntimeCatalog.micro_interaction(id)
        return MICRO_BUS_MAP[id.to_s] unless entry

        handler = entry["handler"].to_s
        return nil unless handler == "ruby" || handler == "both"

        map = MICRO_BUS_MAP[entry["id"].to_s] || MICRO_BUS_MAP[id.to_s]
        map || {
          event: "master:visual",
          mode: entry["category"].to_s,
          entropy: 0.3,
          confidence: 0.7,
        }
      end

      def normalize_felt_state(state)
        src = state.is_a?(Hash) ? state : {}
        {
          mood: (src[:mood] || src["mood"]).to_s.presence || "neutral",
          mode: (src[:mode] || src["mode"]).to_s.presence || "idle",
          entropy: float_or(src[:entropy] || src["entropy"], 0.35),
          confidence: float_or(src[:confidence] || src["confidence"], 0.75),
          arousal: float_or(src[:arousal] || src["arousal"], 0.5),
          valence: float_or(src[:valence] || src["valence"], 0.05),
          vertical: (src[:vertical] || src["vertical"]).to_s.presence,
        }
      end

      def felt_history_from_session(session)
        return { turn_count: 0, recent_entropy_avg: 0.35, retrieval: nil, council: nil } unless session

        messages = session.respond_to?(:messages) ? Array(session.messages) : []
        turn_count = messages.count { |m| (m[:role] || m["role"]).to_s == "user" }
        entropies = messages.last(8).filter_map do |m|
          meta = m[:felt_sense] || m["felt_sense"]
          next unless meta.is_a?(Hash)

          (meta[:entropy] || meta["entropy"]).to_f
        end
        avg = entropies.empty? ? 0.35 : (entropies.sum / entropies.size)

        {
          turn_count: turn_count,
          recent_entropy_avg: avg.round(3),
          retrieval: session.respond_to?(:retrieval_confidence) ? { score: session.retrieval_confidence } : nil,
          council: session.respond_to?(:council_confidence) ? { score: session.council_confidence } : nil,
        }
      rescue StandardError
        { turn_count: 0, recent_entropy_avg: 0.35, retrieval: nil, council: nil }
      end

      def float_or(value, fallback)
        num = value.to_f
        value.nil? || (num.zero? && value.to_s !~ /\A-?\d/) ? fallback : num
      end
      private_class_method :float_or
    end
  end
end