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
          "ms" => { "female" => "yasmin", "male" => "osman" },
        },
        "post_chain" => nil,
        "prosody" => {
          "melody" => {
            "rate" => ["-1%", "+2%", "+1%", "+3%", "0%", "-2%", "-1%", "+1%", "0%", "+2%"],
            "pitch_hz" => [0, 6, 10, 6, 0, -6, -10, -6, 3, 0],
          },
          "pitch_reference_hz" => 180,
        },
        "bed" => nil,
      }.freeze

      module_function

      def data
        @data ||= begin
          raw = Master.load_yaml(Master.data_path("voice.yml"), default: {}) || {}
          base = FALLBACK.merge((raw["tts"] || {}).transform_keys(&:to_s))
          @profile_name = chosen_profile(base)
          overlay = base["profiles"].is_a?(Hash) ? base["profiles"][@profile_name] : nil
          warn_unknown_profile unless @profile_name.empty? || overlay.is_a?(Hash)
          overlay.is_a?(Hash) ? deep_merge(base, overlay) : base
        end
      end

      def reload!
        @data = nil
        data
      end

      # The profile in force: MASTER_TTS_PROFILE wins over `profile:` in voice.yml.
      # Empty when neither is set, which leaves the voice exactly as declared.
      def profile_name
        data
        @profile_name.to_s
      end

      def chosen_profile(base)
        named = ENV["MASTER_TTS_PROFILE"].to_s.strip
        named = base["profile"].to_s.strip if named.empty?
        named.downcase
      end

      def deep_merge(base, overlay)
        base.merge(overlay) { |_key, kept, laid| kept.is_a?(Hash) && laid.is_a?(Hash) ? deep_merge(kept, laid) : laid }
      end

      # A misspelt profile must not pass for the default voice without a word.
      def warn_unknown_profile
        return unless defined?(Master::Trace::Dmesg)

        Master::Trace::Dmesg.once("voice0", "unknown MASTER_TTS_PROFILE #{@profile_name.inspect}, speaking the default voice")
      end

      # What a profile adds beyond the chain, for builders an -af chain cannot
      # express. An empty hash means no layering.
      def layers
        value = data["layers"]
        value.is_a?(Hash) ? value : {}
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

      # The room the voice speaks in: early reflections on a stereo image,
      # declared in voice.yml `room:`. Empty when switched off
      # (MASTER_TTS_PROFILE=dry), which leaves the dry voice.
      def room
        value = data["room"]
        value.is_a?(Hash) && value["enabled"] != false && !value.empty? ? value : {}
      end

      # post_chain plus the room, as ffmpeg runs it. The browser is handed the
      # two apart (browser_payload) because it builds the room from WebAudio.
      def shaped_chain
        wet = room_chain
        wet ? [post_chain, wet].compact.join(",") : post_chain
      end

      # Mono to stereo, a short delay on one side for width, reflections as
      # parallel echoes, fixed makeup gain, and the limiter again because the
      # reflections add level above the chain's own ceiling.
      def room_chain
        cfg = room
        return nil if cfg.empty?

        delays = Array(cfg["reflections_ms"]).map { |ms| format("%g", ms) }.join("|")
        decays = Array(cfg["decays"]).map { |value| format("%g", value) }.join("|")
        [
          "pan=stereo|c0=0.707*c0|c1=0.707*c0",
          "adelay=0|#{cfg.fetch('width_ms', 0).to_i}",
          "aecho=1:#{format('%g', cfg.fetch('out_gain', 0.9))}:#{delays}:#{decays}",
          "volume=#{format('%g', cfg.fetch('gain_db', 0))}dB",
          "alimiter=limit=0.98",
        ].join(",")
      end

      # voice.yml `face:`, the one home of how both faces attend and shape the
      # mouth. Read at top level, beside `tts:`, so no profile overlays it.
      def face_section(key)
        raw = Master.load_yaml(Master.data_path("voice.yml"), default: {}) || {}
        value = (raw["face"] || {})[key]
        value.is_a?(Hash) ? value : {}
      end

      def awareness = (@awareness ||= face_section("awareness"))
      def mouth = (@mouth ||= face_section("mouth"))

      # True when the mic cannot be hearing MASTER: nothing playing or loading,
      # and the tail after the last sentence has passed. The terminal listens
      # only between utterances; the browser listens while it speaks, so this is
      # the gate every feed of "the user is speaking" goes through.
      def echo_safe?(playing:, loading: false, ms_since_tts_end: nil)
        return false if playing || loading

        tail = awareness.fetch("echo_safe", {}).fetch("tts_tail_ms", 900)
        ms_since_tts_end.nil? || ms_since_tts_end >= tail
      end

      # The viseme a letter makes, by the same rule the browser's setViseme uses:
      # a vowel is itself, a bilabial or labiodental closes the lips, any other
      # letter is the relaxed E.
      def viseme_for(char)
        letter = char.to_s.downcase
        return letter.upcase if %w[a e i o u].include?(letter)

        mouth.fetch("closed_letters", "mbpfwv").include?(letter) && !letter.empty? ? "M" : "E"
      end

      # { "open" => 0..1, "wide" => -1..1 } for a viseme name.
      def mouth_shape(name)
        shapes = mouth.fetch("shapes", {})
        shapes.fetch(name.to_s, shapes.fetch("neutral", { "open" => 0.0, "wide" => 0.0 }))
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
          room:,
          awareness:,
          mouth:,
          prosody:,
          bed:,
          profile: profile_name,
          layers:,
          persona_affects_text_only: persona_affects_text_only?,
          stream_live_default: stream_live_default?,
          default_rate:,
          default_pitch:,
        }
      end
    end
  end
end
