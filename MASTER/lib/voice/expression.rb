# frozen_string_literal: true

module Master
  module Voice
  # Expression — authoritative mapping from runtime signals to TTS + face/particle expression.
  # Single source for how council reversibility, speech register (creative vs factual),
  # Osman creative styles, entropy/pressure, and mood arc become rich parameters for
  # both edge-tts prosody and the ParticleKernel (arousal, pressure, valence, breath,
  # eye behavior, ecology spirits, terrain, etc.).
  #
  # This is the clean extraction point for the large body of interconnectedness ideas
  # in runtime_ui_direction.md. All future style-specific, reversibility-weighted,
  # pre-speech anticipation, post-speech decay, vertical timbre, and mood persistence
  # logic belongs here.
    module Expression
      CREATIVE_STYLES = %i[dramatic intense energetic storyteller ethereal].freeze
      LOW_STYLES      = %i[whispered intimate robotic calm].freeze

      CONFIDENCE_WEIGHTS = { verdict: 0.45, retrieval: 0.30, council: 0.25 }.freeze
      VOWEL_SHAPES = { "a" => "A", "e" => "E", "i" => "I", "o" => "O", "u" => "U" }.freeze

      module_function

      # Main entry for text → expression profile.
      # Used by Speech.synthesize and chat paths.
      def for_text(text, risk: nil, reversibility: nil)
        t = text.to_s.strip
        register = (t.split.size > 35 || t.match?(/\b(grand|beautiful|story|deep|feel|world)\b/i)) ? :creative : :factual

        base_style = if register == :creative
                       CREATIVE_STYLES[t.hash % CREATIVE_STYLES.size]
                     else
                       :clear
                     end

        face = face_params_for(register: register, style: base_style, risk: risk, reversibility: reversibility)

        {
          register: register,
          style: base_style,
          face: face,
          breath_boost: register == :creative ? 0.25 : 0.0,
          eye_attention: register == :creative ? 0.15 : 0.0,
        }
      end

      # For explicit council events (especially low-reversibility / high-stakes work).
      def for_council(risk:, reversibility:)
        weight = (reversibility == :low || risk == :critical) ? 0.35 : 0.12
        {
          emotion: emotion_for(mode: :council, risk: risk, reversibility: reversibility),
          spirit_charge_boost: weight,
          mouth_pressure: weight * 0.8,
          eye_confidence_drop: weight * 0.6,
          terrain_jaggedness: (risk == :critical) ? 0.4 : 0.15,
        }
      end

      # Maps genuine runtime signals onto the four fields the face actually renders
      # via deriveBlendFromEmotion (valence, arousal, confidence, focus).
      def emotion_for(mode: nil, risk: nil, reversibility: nil, verdict: nil, score: nil)
        high_stakes = reversibility == :low || %i[high critical].include?(risk)
        failing = mode.to_s.match?(/veto|error|fail|rollback|block/)

        confidence =
          case verdict
          when :pass then 0.95
          when :block then 0.30
          when :review then 0.60
          else high_stakes ? 0.50 : 0.85
          end
        confidence = score.to_f if verdict.nil? && score
        confidence -= 0.25 if failing

        valence =
          if verdict == :pass then 0.40
          elsif verdict == :block || failing then -0.35
          else 0.05
          end

        {
          confidence: confidence.clamp(0.0, 1.0),
          valence: valence.clamp(-1.0, 1.0),
          arousal: (high_stakes || failing) ? 0.85 : 0.45,
          focus: high_stakes ? 0.90 : 0.50,
        }
      end

      # Evidence events carry a rendered emotion patch built from the verdict.
      def for_evidence(verdict:, score: nil)
        { emotion: emotion_for(verdict: verdict, score: score) }
      end

      # Rich visual deltas for a specific Osman creative style (used when tts:style:active fires).
      def for_tts_style(style_name)
        s = style_name.to_s.downcase.to_sym
        hi = CREATIVE_STYLES.include?(s) || %i[intense energetic].include?(s)
        lo = LOW_STYLES.include?(s)

        {
          arousal: hi ? 1.0 : lo ? 0.3 : 0.7,
          pressure: hi ? 0.85 : lo ? 0.25 : 0.6,
          breath_boost: hi ? 0.35 : lo ? -0.15 : 0.0,
          valence: lo ? 0.2 : 0.0,
          blendshapes: blendshapes_for(s),
          decay_rate: decay_rate_for(s),
        }
      end

      def blendshapes_for(style_name)
        s = style_name.to_s.downcase.to_sym
        hi = CREATIVE_STYLES.include?(s) || %i[intense energetic].include?(s)
        lo = LOW_STYLES.include?(s)

        {
          jaw: hi ? 0.78 : lo ? 0.22 : 0.55,
          smile: hi ? 0.38 : lo ? 0.12 : 0.28,
          brow: hi ? 0.68 : lo ? 0.18 : 0.42,
          lid_open: hi ? 0.88 : lo ? 0.52 : 0.72,
        }
      end

      def for_pre_speech(style:, text: nil)
        base = for_tts_style(style)
        spike = text.to_s.length > 120 ? 0.30 : 0.22
        {
          arousal: [(base[:arousal] || 0.7) + spike, 1.0].min,
          eye_attention: 0.38,
          breath_boost: (base[:breath_boost] || 0.0) + 0.18,
          style: style.to_s,
        }
      end

      def for_post_speech(style:)
        rate = decay_rate_for(style)
        lo = LOW_STYLES.include?(style.to_s.downcase.to_sym)
        {
          decay_rate: rate,
          linger_ms: ((1.0 - rate) * 1400).to_i,
          arousal_floor: lo ? 0.22 : 0.40,
          pressure_floor: lo ? 0.15 : 0.30,
        }
      end

      def viseme_hints(text)
        clean = text.to_s.downcase.gsub(/[^a-zæøåéáà]/i, "")
        return [] if clean.empty?

        hints = []
        clean.each_char do |c|
          shape = VOWEL_SHAPES[c] || (c.match?(/[mbpfvw]/i) ? "M" : "E")
          ms = shape == "M" ? 55 : 85
          if hints.last && hints.last[:shape] == shape
            hints.last[:ms] += ms
          else
            hints << { shape: shape, amp: 0.85, ms: ms }
          end
        end
        hints
      end

      VERTICAL_BIASES = {
        marketplace: { arousal: 0.08, pressure: 0.14, valence: -0.05 },
        dating: { arousal: -0.06, valence: 0.18, attention: 0.12 },
        tv: { arousal: 0.04, scanline: 0.22 }
      }.freeze

      COUNCIL_PERSONA_EXPRESSION = {
        "Architect" => { arousal: 0.62, valence: 0.12, attention: 0.78, pressure: 0.55 },
        "Skeptic" => { arousal: 0.74, valence: -0.18, attention: 0.82, pressure: 0.68 },
        "Pragmatist" => { arousal: 0.48, valence: 0.05, attention: 0.6, pressure: 0.42 },
        "Security" => { arousal: 0.7, valence: -0.22, attention: 0.85, pressure: 0.72 },
        "User" => { arousal: 0.4, valence: 0.2, attention: 0.55, pressure: 0.35 },
        "Mentor" => { arousal: 0.36, valence: 0.28, attention: 0.5, pressure: 0.3 }
      }.freeze

      def for_vertical(app)
        VERTICAL_BIASES[app.to_s.downcase.to_sym] || {}
      end

      def mood_arc(history:)
        entries = Array(history)
        return { arousal: 0.45, valence: 0.0, entropy: 0.2, decay_rate: 0.65 } if entries.empty?

        entropies = entries.map { |h| (h[:entropy] || h["entropy"] || 0.2).to_f }
        valences = entries.map { |h| (h[:valence] || h["valence"] || 0.0).to_f }
        arousals = entries.map { |h| (h[:arousal] || h["arousal"] || 0.4).to_f }
        mean_entropy = entropies.sum / entropies.length
        mean_valence = valences.sum / valences.length
        mean_arousal = arousals.sum / arousals.length

        {
          arousal: mean_arousal.clamp(0.0, 1.0),
          valence: mean_valence.clamp(-1.0, 1.0),
          entropy: mean_entropy.clamp(0.0, 1.0),
          decay_rate: mean_entropy > 0.55 ? 0.32 : 0.68
        }
      end

      def for_council_persona(persona_id)
        base = COUNCIL_PERSONA_EXPRESSION[persona_id.to_s] || COUNCIL_PERSONA_EXPRESSION["Pragmatist"]
        lane = CouncilFace::PERSONAS.dig(persona_id.to_s, :viseme_lane) || :center
        {
          **base,
          emotion: emotion_for(mode: :council),
          viseme_lane: lane,
          viseme_plan: [],
          eye_confidence_drop: persona_id.to_s == "Skeptic" ? 0.22 : 0.12
        }
      end

      def fuse_confidence(sources)
        src = sources.is_a?(Hash) ? sources : {}
        total_w = 0.0
        fused = 0.0

        CONFIDENCE_WEIGHTS.each do |key, weight|
          raw = src[key] || src[key.to_s]
          next if raw.nil?

          score =
            case raw
            when Hash then raw[:score] || raw["score"] || raw[:confidence] || raw["confidence"]
            when Symbol then raw == :pass ? 0.95 : raw == :block ? 0.30 : 0.60
            else raw
            end
          next if score.nil?

          fused += score.to_f * weight
          total_w += weight
        end

        total_w.positive? ? (fused / total_w).clamp(0.0, 1.0) : 0.75
      end

      private_class_method def decay_rate_for(style_name)
        s = style_name.to_s.downcase.to_sym
        return 0.12 if s == :dramatic
        return 0.88 if s == :whispered
        return 0.72 if LOW_STYLES.include?(s)
        return 0.28 if CREATIVE_STYLES.include?(s)

        0.50
      end

      private_class_method def face_params_for(register:, style:, risk:, reversibility:)
        creative = register == :creative
        high_stakes = (reversibility == :low || risk == :critical || risk == :high)

        {
          arousal: creative ? 0.9 : 0.55,
          pressure: high_stakes ? 0.7 : (creative ? 0.65 : 0.4),
          valence: creative ? 0.25 : -0.05,
          attention: high_stakes ? 0.85 : 0.6,
          breath: creative ? 1.35 : 1.0,
        }
      end
    end
  end
end