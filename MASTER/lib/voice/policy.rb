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
        "default_rate" => "-5%",
        "default_pitch" => "+0Hz",
        "operator_log" => { "voice" => "christopher", "rate" => "-10%", "pitch" => "+0Hz" },
        "rotation" => %w[jenny],
        "language_voices" => { "en" => "jenny", "nb" => "pernille", "ms" => "yasmin" },
        "language_voice_families" => {
          "en" => { "female" => "jenny", "male" => "andrew" },
          "nb" => { "female" => "pernille", "male" => "finn" },
          "ms" => { "female" => "yasmin", "male" => "osman" }
        },
        "post_chain" => nil,
        "prosody" => {
          "melody" => {
            "rate" => ["-1%", "+2%", "+1%", "+3%", "0%", "-2%", "-1%", "+1%", "0%", "+2%"],
            "pitch_hz" => [0, 6, 10, 6, 0, -6, -10, -6, 3, 0]
          },
          "pitch_reference_hz" => 180
        },
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

      def language_voice_families
        value = data["language_voice_families"]
        return {} unless value.is_a?(Hash)

        value.each_with_object({}) do |(language, family), result|
          next unless family.is_a?(Hash)
          result[language.to_s.strip.downcase] = family.each_with_object({}) do |(gender, voice), row|
            key = voice.to_s.strip.downcase
            row[gender.to_s.strip.downcase] = key.to_sym unless key.empty?
          end
        end
      end

      def language_voices
        value = data["language_voices"]
        return {} unless value.is_a?(Hash)

        value.each_with_object({}) do |(language, voice), result|
          key = voice.to_s.strip.downcase
          result[language.to_s.strip.downcase] = key.to_sym unless key.empty?
        end
      end

      def voice_for_language(language, gender: nil)
        lang = language.to_s.strip.downcase
        family = language_voice_families[lang]
        requested_gender = gender.to_s.strip.downcase
        requested_gender = ENV.fetch("MASTER_TTS_GENDER", "female").to_s.strip.downcase if requested_gender.empty?
        if family
          chosen = family[requested_gender] || family["female"] || family.values.first
          return chosen if Speech::VOICES.key?(chosen)
        end

        voice = language_voices[lang]
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
      # Prosody knobs live beside the rest of the TTS policy so melody and
      # engine adapters do not grow a second configuration source.
      def prosody
        value = data["prosody"]
        value.is_a?(Hash) ? value : FALLBACK["prosody"]
      end

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

      def operator_log
        value = data["operator_log"]
        value.is_a?(Hash) ? value : FALLBACK["operator_log"]
      end

      def operator_log_voice
        key = operator_log["voice"].to_s.strip.downcase.to_sym
        Speech::VOICES.key?(key) ? key : FALLBACK["operator_log"]["voice"].to_sym
      end

      def operator_log_rate
        operator_log["rate"].to_s.strip.empty? ? FALLBACK["operator_log"]["rate"] : operator_log["rate"].to_s
      end

      def operator_log_pitch
        operator_log["pitch"].to_s.strip.empty? ? FALLBACK["operator_log"]["pitch"] : operator_log["pitch"].to_s
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
          language_voice_families: language_voice_families.transform_values { |family| family.transform_values(&:to_s) },
          voices: voice_aliases,
          post_chain:,
          prosody:,
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
