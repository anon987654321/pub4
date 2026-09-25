# frozen_string_literal: true

require "yaml"
require_relative "language"

module Master
  module Voice
    # Single source of truth for TTS voice policy (data/voice.yml tts section).
    # Persona YAML may list other voices for LLM style; synthesis always uses this policy.
    module Policy
      # Keep in step with data/voice.yml: this hash is what a missing or
      # unreadable voice.yml falls back to, so a stale entry here reintroduces
      # the exact voice/neural mismatch the file's comment describes. post_chain
      # is nil so an unreadable voice.yml speaks dry rather than failing.
      FALLBACK = {
        "single_voice" => "jenny",
        "neural" => "en-US-JennyNeural",
        "persona_affects_text_only" => true,
        "stream_live_default" => true,
        "default_rate" => "-7%",
        "default_pitch" => "+0Hz",
        "rotation" => %w[jenny],
        "language_voices" => { "en" => "jenny", "nb" => "pernille" },
        "post_chain" => nil,
        "bed" => nil,
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

      # The voices MASTER may speak in, when the operator has declared more than
      # one.
      #
      # `single_voice` stayed the contract for as long as there was one voice,
      # and every reader still agrees with it — an empty or absent `rotation`
      # leaves this returning exactly that one name, so nothing downstream sees
      # a change. What it is NOT is a persona list: personas affect text only
      # (`persona_affects_text_only`), and a rotation affects only which mouth
      # says the same sentence.
      def rotation_keys
        Array(data["rotation"]).map { |name| name.to_s.strip.downcase.to_sym }.reject { |name| name == :"" }
      end

      def rotating? = rotation_keys.size > 1

      def language_voices
        value = data["language_voices"]
        return {} unless value.is_a?(Hash)

        value.each_with_object({}) do |(language, voice), result|
          key = voice.to_s.strip.downcase
          result[language.to_s.strip.downcase] = key.to_sym unless key.empty?
        end
      end

      def voice_for_language(language)
        voice = language_voices[language.to_s.strip.downcase]
        return single_voice_key if voice.nil?

        Speech::VOICES.key?(voice) ? voice : single_voice_key
      end

      def voice_for_text(text)
        voice_for_language(Language.detect(text))
      end

      # A voice for one utterance. Round-robin for reading paragraphs:
      # alternates between available voices to create a dual-narrator effect.
      def voice_for_utterance
        return single_voice_key unless rotating?

        @rotation_idx ||= 0
        keys = rotation_keys
        voice = keys[@rotation_idx % keys.size]
        @rotation_idx += 1
        voice
      end

            def neural_voice
              data["neural"].to_s.strip.empty? ? FALLBACK["neural"] : data["neural"].to_s
            end

      # The ffmpeg chain applied after synthesis, or nil when none is declared.
      #
      # Nil rather than an empty string, so a caller writes `if chain` and a
      # missing declaration cannot be confused with a chain that does nothing.
      def post_chain
        value = data["post_chain"].to_s.strip
        value.empty? ? nil : value
      end

      # The musical bed, as declared. Nil when absent; the renderer is the
      # caller's, because MASTER's web face and a terminal narrator mix audio
      # in entirely different ways.
      def bed
        row = data["bed"]
        row.is_a?(Hash) && !row.empty? ? row : nil
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

      # Short name to Edge voice, from Speech::VOICES. The face resolved the
      # names in a table of its own that had already lost `davis`; a name the
      # server can speak and the face cannot resolve is the drift this payload
      # exists to prevent, so the face reads the server's table instead.
      def voice_aliases
        Speech::VOICES.reject { |name, _| name.to_s.end_with?("Neural") }.transform_keys(&:to_s)
      end

      # edge-tts --volume. Raises the synthesised signal itself, so the browser
      # chain is not the only place loudness comes from.
      def browser_payload
        {
          single_voice: single_voice_key.to_s,
          neural: neural_voice,
          rotation: rotation_keys.map(&:to_s),
          language_voices: language_voices.transform_values(&:to_s),
          voices: voice_aliases,
          post_chain:,
          bed:,
          persona_affects_text_only: persona_affects_text_only?,
          stream_live_default: stream_live_default?,
          default_rate:,
          default_pitch:,
        }
      end
    end
  end
end
