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
      LOW_STYLES = %i[whispered intimate robotic calm].freeze

      CONFIDENCE_WEIGHTS = { verdict: 0.45, retrieval: 0.30, council: 0.25 }.freeze
      VOWEL_SHAPES = { "a" => "A", "e" => "E", "i" => "I", "o" => "O", "u" => "U" }.freeze
      CREATIVE_WORD_COUNT_THRESHOLD = 35

      module_function

      # Main entry for text → expression profile.
      # Used by Speech.synthesize and chat paths.
      def for_text(text, risk: nil, reversibility: nil)
        t = text.to_s.strip
        register = (t.split.size > CREATIVE_WORD_COUNT_THRESHOLD || t.match?(/\b(grand|beautiful|story|deep|feel|world)\b/i)) ? :creative : :factual

        base_style = if register == :creative
                       CREATIVE_STYLES[t.hash % CREATIVE_STYLES.size]
                     else
                       :clear
                     end

        face = face_params_for(register:, style: base_style, risk:, reversibility:)

        {
          register:,
          style: base_style,
          face:,
          breath_boost: register == :creative ? 0.25 : 0.0,
          eye_attention: register == :creative ? 0.15 : 0.0,
        }
      end

      # For explicit council events (especially low-reversibility / high-stakes work).
      def for_council(risk:, reversibility:)
        weight = (reversibility == :low || risk == :critical) ? 0.35 : 0.12
        {
          emotion: emotion_for(mode: :council, risk:, reversibility:),
          spirit_charge_boost: weight,
          mouth_pressure: weight * 0.8,
          eye_confidence_drop: weight * 0.6,
          terrain_jaggedness: (risk == :critical) ? 0.4 : 0.15,
        }
      end

      # Maps genuine runtime signals onto the four fields the face renders
      # via deriveBlendFromEmotion (valence, arousal, confidence, focus).
      def emotion_for(mode: nil, risk: nil, reversibility: nil, verdict: nil, score: nil)
        high_stakes = reversibility == :low || %i[high critical].include?(risk)
        failing = mode.to_s.match?(/veto|error|fail|rollback|block/)

        {
          confidence: confidence_for(verdict:, score:, high_stakes:, failing:).clamp(0.0, 1.0),
          valence: valence_for(verdict:, failing:).clamp(-1.0, 1.0),
          arousal: (high_stakes || failing) ? 0.85 : 0.45,
          focus: high_stakes ? 0.90 : 0.50,
        }
      end

      def confidence_for(verdict:, score:, high_stakes:, failing:)
        confidence =
          case verdict
          when :pass then 0.95
          when :block then 0.30
          when :review then 0.60
          else high_stakes ? 0.50 : 0.85
          end
        confidence = score.to_f if verdict.nil? && score
        confidence -= 0.25 if failing
        confidence
      end

      def valence_for(verdict:, failing:)
        if verdict == :pass then 0.40
        elsif verdict == :block || failing then -0.35
        else 0.05
        end
      end

      # Evidence events carry a rendered emotion patch built from the verdict.
      def for_evidence(verdict:, score: nil)
        { emotion: emotion_for(verdict:, score:) }
      end

      # Rich visual deltas for a specific Osman creative style (used when tts:style:active fires).
      def for_tts_style(style_name)
        s = style_name.to_s.downcase.to_sym
        hi, lo = style_tier(s)

        {
          arousal: tier_value(hi, lo, hi_val: 1.0, lo_val: 0.3, mid_val: 0.7),
          pressure: tier_value(hi, lo, hi_val: 0.85, lo_val: 0.25, mid_val: 0.6),
          breath_boost: tier_value(hi, lo, hi_val: 0.35, lo_val: -0.15, mid_val: 0.0),
          valence: lo ? 0.2 : 0.0,
          blendshapes: blendshapes_for(s),
          decay_rate: decay_rate_for(s),
        }
      end

      def style_tier(s)
        hi = CREATIVE_STYLES.include?(s) || %i[intense energetic].include?(s)
        lo = LOW_STYLES.include?(s)
        [hi, lo]
      end

      def tier_value(hi, lo, hi_val:, lo_val:, mid_val:)
        return hi_val if hi
        return lo_val if lo

        mid_val
      end

      def blendshapes_for(style_name)
        s = style_name.to_s.downcase.to_sym
        hi, lo = style_tier(s)

        {
          jaw: tier_value(hi, lo, hi_val: 0.78, lo_val: 0.22, mid_val: 0.55),
          smile: tier_value(hi, lo, hi_val: 0.38, lo_val: 0.12, mid_val: 0.28),
          brow: tier_value(hi, lo, hi_val: 0.68, lo_val: 0.18, mid_val: 0.42),
          lid_open: tier_value(hi, lo, hi_val: 0.88, lo_val: 0.52, mid_val: 0.72),
        }
      end

      def for_pre_speech(style:, text: nil)
        base = for_tts_style(style)
        spike = text.to_s.length > 120 ? 0.30 : 0.22
        {
          arousal: [base.fetch(:arousal, 0.7) + spike, 1.0].min,
          eye_attention: 0.38,
          breath_boost: base.fetch(:breath_boost, 0.0) + 0.18,
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

      STYLE_RATE_SCALE = {
        whispered: 1.35, ethereal: 1.22, dramatic: 1.18, calm: 1.08,
        energetic: 0.82, brief: 0.88, intense: 0.90, storyteller: 1.05,
      }.freeze

      CONSONANT_SHAPES = {
        "m" => "M", "b" => "M", "p" => "M",
        "f" => "M", "v" => "M", "w" => "O",
      }.freeze

      def viseme_hints(text)
        clean = text.to_s.downcase.gsub(/[^a-zæøåéáà]/i, "")
        return [] if clean.empty?

        hints = []
        clean.each_char do |c|
          shape = VOWEL_SHAPES[c] || CONSONANT_SHAPES[c] || "E"
          ms = if shape == "M"
55
else
(VOWEL_SHAPES[c] ? 85 : 62)
end
          amp = shape == "M" ? 0.72 : 0.85
          if hints.last && hints.last[:shape] == shape
            hints.last[:ms] += ms
          else
            hints << { shape:, amp:, ms: }
          end
        end
        hints
      end

      # Duration-aware viseme frames for bus + X-TTS-Visemes headers.
      def viseme_plan(text, style: nil, rate: nil)
        hints = viseme_hints(text)
        return [] if hints.empty?

        scale = viseme_timing_scale(style, rate)
        t = 0
        hints.map do |hint|
          ms = [(hint[:ms] * scale).round, 28].max
          frame = { shape: hint[:shape], amp: hint[:amp], t:, ms: }
          t += ms
          frame
        end
      end

      def viseme_stream(text, style: nil, rate: nil)
        plan = viseme_plan(text, style:, rate:)
        {
          visemes: viseme_hints(text),
          viseme_plan: plan,
          duration_ms: plan.last ? plan.last[:t] + plan.last[:ms] : 0,
          source: "expression_phoneme_heuristic",
        }
      end

      # Layer whispered breath under ethereal lift for chained creative styles.
      def chain_styles(primary, secondary = nil)
        primary_style = primary.to_s.downcase.to_sym
        secondary_style = secondary.to_s.downcase.to_sym if secondary
        base = for_tts_style(primary_style)
        return base unless secondary_style && STYLES_CHAINABLE.include?(secondary_style)

        under = for_tts_style(secondary_style)
        {
          **base,
          arousal: [base.fetch(:arousal, 0.5) * 0.82 + under.fetch(:arousal, 0.3) * 0.18, 1.0].min,
          pressure: [base.fetch(:pressure, 0.4) * 0.75 + under.fetch(:pressure, 0.2) * 0.25, 1.0].min,
          breath_boost: base.fetch(:breath_boost, 0.0) + under.fetch(:breath_boost, 0.0) * 0.45,
          blendshapes: blendshapes_for(primary_style).merge(blendshapes_for(secondary_style)) { |_k, a, b| ((a + b) * 0.5).clamp(0.0, 1.0) },
          decay_rate: [base.fetch(:decay_rate, 0.5), under.fetch(:decay_rate, 0.5)].max,
          chained: [primary_style, secondary_style],
        }
      end

      STYLES_CHAINABLE = %i[whispered ethereal intimate calm robotic].freeze

      VOICE_IDLE_SIGNATURES = {
        osman: { breath: 1.08, saccade: 0.24, pulse_floor: 0.14, blink_ms: 3200 },
        ryan: { breath: 0.96, saccade: 0.18, pulse_floor: 0.08, blink_ms: 2800 },
        finn: { breath: 1.02, saccade: 0.20, pulse_floor: 0.10, blink_ms: 3000 },
        andrew: { breath: 0.94, saccade: 0.16, pulse_floor: 0.07, blink_ms: 2600 },
        # Matches face.part1.txt's 'nb-NO-PernilleNeural' entry, which carries the
        # deliberate "future-human: composed, steady gaze, still baseline, slow
        # deliberate blink" tuning. This table had generic values instead, so the
        # face idled differently depending on which side computed the signature.
        pernille: { breath: 0.90, saccade: 0.10, pulse_floor: 0.05, blink_ms: 4200 },
        ezinne: { breath: 1.10, saccade: 0.26, pulse_floor: 0.12, blink_ms: 3400 },
        wayne: { breath: 0.92, saccade: 0.15, pulse_floor: 0.06, blink_ms: 2500 },
      }.freeze

      def idle_signature_for(voice)
        key = Speech.resolve_voice(voice)
        VOICE_IDLE_SIGNATURES[key] || { breath: 1.0, saccade: 0.2, pulse_floor: 0.1, blink_ms: 3000 }
      end

      def council_spirit_radius(risk: nil, reversibility: nil, persona_count: 5)
        base = 1.0
        base += 0.12 if reversibility == :low
        base += 0.08 if %i[high critical].include?(risk)
        base + [persona_count - 3, 0].max * 0.04
      end

      VERTICAL_BIASES = {
        marketplace: { arousal: 0.08, pressure: 0.14, valence: -0.05 },
        dating: { arousal: -0.06, valence: 0.18, attention: 0.12 },
        tv: { arousal: 0.04, scanline: 0.22 },
      }.freeze

      COUNCIL_PERSONA_EXPRESSION = {
        "Architect" => { arousal: 0.62, valence: 0.12, attention: 0.78, pressure: 0.55 },
        "Skeptic" => { arousal: 0.74, valence: -0.18, attention: 0.82, pressure: 0.68 },
        "Pragmatist" => { arousal: 0.48, valence: 0.05, attention: 0.6, pressure: 0.42 },
        "Security" => { arousal: 0.7, valence: -0.22, attention: 0.85, pressure: 0.72 },
        "User" => { arousal: 0.4, valence: 0.2, attention: 0.55, pressure: 0.35 },
        "Mentor" => { arousal: 0.36, valence: 0.28, attention: 0.5, pressure: 0.3 },
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
          decay_rate: mean_entropy > 0.55 ? 0.32 : 0.68,
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
          eye_confidence_drop: persona_id.to_s == "Skeptic" ? 0.22 : 0.12,
        }
      end

      def fuse_confidence(sources)
        src = sources.is_a?(Hash) ? sources : {}
        total_w = 0.0
        fused = 0.0

        CONFIDENCE_WEIGHTS.each do |key, weight|
          score = confidence_score_for(key, src)
          next if score.nil?

          fused += score.to_f * weight
          total_w += weight
        end

        total_w.positive? ? (fused / total_w).clamp(0.0, 1.0) : 0.75
      end

      def confidence_score_for(key, src)
        raw = src[key] || src[key.to_s]
        return if raw.nil?

        case raw
        when Hash then raw[:score] || raw["score"] || raw[:confidence] || raw["confidence"]
        when Symbol
          if raw == :pass
            0.95
          elsif raw == :block
            0.30
          else
            0.60
          end
        else raw
        end
      end

      private_class_method def viseme_timing_scale(style, rate)
        style_key = style.to_s.downcase.to_sym if style
        base = STYLE_RATE_SCALE[style_key] || 1.0
        return base unless rate

        pct = rate.to_s.delete("%").to_i
        return base if pct.zero?

        rate_factor = 1.0 - (pct / 100.0) * 0.35
        (base * rate_factor).clamp(0.55, 1.65)
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
          pressure: if high_stakes
0.7
else
(creative ? 0.65 : 0.4)
end,
          valence: creative ? 0.25 : -0.05,
          attention: high_stakes ? 0.85 : 0.6,
          breath: creative ? 1.35 : 1.0,
        }
      end
    end
  end
end
