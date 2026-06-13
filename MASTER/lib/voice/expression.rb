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
          spirit_charge_boost: weight,
          mouth_pressure: weight * 0.8,
          eye_confidence_drop: weight * 0.6,
          terrain_jaggedness: (risk == :critical) ? 0.4 : 0.15,
        }
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
        }
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
