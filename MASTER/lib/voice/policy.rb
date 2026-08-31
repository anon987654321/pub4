# frozen_string_literal: true

require "yaml"

module Master
  module Voice
    # Single source of truth for TTS voice policy (data/voice.yml tts section).
    # Persona YAML may list other voices for LLM style; synthesis always uses this policy.
    module Policy
      # Keep in step with data/voice.yml: this hash is what a missing or
      # unreadable voice.yml falls back to, so a stale entry here reintroduces
      # the exact voice/neural mismatch the file's comment describes.
      FALLBACK = {
        "single_voice" => "osman",
        "neural" => "ms-MY-OsmanNeural",
        "persona_affects_text_only" => true,
        "stream_live_default" => true,
        "default_rate" => "-22%",
        "default_pitch" => "-35Hz",
      }.freeze

      module_function

      def data
        @data ||= begin
          raw = Master.load_yaml(Master.data_path("voice.yml"), default: {}) || {}
          FALLBACK.merge((raw["tts"] || {}).transform_keys(&:to_s))
        end
      end

      def reload!
        @data = nil
        data
      end

      def single_voice_key
        sym = data["single_voice"].to_s.strip.downcase.to_sym
        sym = FALLBACK["single_voice"].to_sym if sym == :""
        sym
      end

      def neural_voice
        data["neural"].to_s.strip.empty? ? FALLBACK["neural"] : data["neural"].to_s
      end

      def persona_affects_text_only?
        data["persona_affects_text_only"] != false
      end

      def stream_live_default?
        data["stream_live_default"] == true
      end

      def default_rate
        data["default_rate"].to_s
      end

      def default_pitch
        data["default_pitch"].to_s
      end

      # edge-tts --volume. Raises the synthesised signal itself, so the browser
      # chain is not the only place loudness comes from.
      def browser_payload
        {
          single_voice: single_voice_key.to_s,
          neural: neural_voice,
          persona_affects_text_only: persona_affects_text_only?,
          stream_live_default: stream_live_default?,
          default_rate:,
          default_pitch:,
        }
      end
    end
  end
end
