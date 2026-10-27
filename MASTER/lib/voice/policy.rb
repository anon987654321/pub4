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
        "single_voice" => "christopher",
        "neural" => "en-US-ChristopherNeural",
        "persona_affects_text_only" => true,
        "stream_live_default" => true,
        "default_rate" => "-6%",
        "default_pitch" => "+0Hz",
        "operator_log" => { "voice" => "christopher", "rate" => "-10%", "pitch" => "+0Hz" },
        "rotation" => %w[christopher],
        "language_voices" => { "en" => "christopher", "nb" => "pernille", "ms" => "yasmin" },
        "language_voice_families" => {
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

      # The `human` profile's clause pipeline (Voice::Human). Off for every
      # other voice, so the default never passes through it.
      def human_pipeline?
        data["human_pipeline"] == true
      end

      # The breath before a long sentence in the human pipeline; nil when absent.
      def breath
        value = data["breath"]
        value.is_a?(Hash) && !value.empty? ? value : nil
      end

      # Characters in the first packet of a reply; 0 keeps sentence packing.
      def first_chunk_chars
        value = data["streaming"]
        value.is_a?(Hash) ? value["first_chunk_chars"].to_i : 0
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
        requested_gender = ENV.fetch("MASTER_TTS_GENDER", "").to_s.strip.downcase if requested_gender.empty?
        # No gender asked for anywhere: the declared language voice is the default.
        family = nil if requested_gender.empty? && language_voices.key?(lang)
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

      # Return the configured voice for one utterance. Rotations remain
      # available for explicit multi-voice setups; the default policy is single-voice.
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

      # post_chain, the dilla rack, the room, the rack's stereo units and the
      # final ceiling, as ffmpeg runs it. The browser is handed the parts apart
      # (browser_payload) because it builds the room and the rack from WebAudio.
      # With the rack off this is post_chain plus the room, as it always was.
      def shaped_chain
        wet = room_chain
        return [post_chain, character_chain, wet].compact.join(",") if !fx_enabled? || fx_units.empty?

        stereo = fx_chain("stereo")
        widen = "pan=stereo|c0=c0|c1=c0" if stereo && wet.nil?
        [post_chain, "volume=#{format('%g', fx_config.fetch('in_db', 0))}dB", fx_chain("mono"), character_chain, wet, widen, stereo,
         "volume=#{format('%g', fx_config.fetch('trim_db', 0))}dB",
         "alimiter=limit=#{format('%g', fx_config.fetch('ceiling', 0.8))}:level=disabled:attack=2:release=50"].compact.join(",")
      end

      # dilla's effects as a rack, voice.yml `dilla_fx`. Off when the section is
      # absent or disabled, when the profile switches it off, or when
      # MASTER_TTS_FX is 0, off, false or no.
      def fx_config
        value = data["dilla_fx"]
        value.is_a?(Hash) ? value : {}
      end

      def fx_enabled?
        return false if %w[0 off false no].include?(ENV["MASTER_TTS_FX"].to_s.strip.downcase)

        fx_config["enabled"] == true
      end

      # The enabled units, each with its %{level} filled in, in rack order.
      def fx_units
        Array(fx_config["units"]).select { |unit| unit.is_a?(Hash) && unit["enabled"] != false && !unit["filter"].to_s.strip.empty? }
                                 .map { |unit| unit.merge("filter" => unit["filter"].to_s.gsub("%{level}", format("%g", unit["level"].to_f))) }
      end

      # One region's units as a single -af chain, nil when it has none. After the
      # last unit of each stage comes that stage's makeup (`stage_trim_db`), so
      # the next stage sees the level dilla's racks are gain-matched at.
      def fx_chain(region)
        return unless fx_enabled?

        units = fx_units.select { |unit| unit.fetch("region", "mono") == region }
        trims = fx_config["stage_trim_db"].is_a?(Hash) ? fx_config["stage_trim_db"] : {}
        parts = units.each_with_index.flat_map do |unit, i|
          trim = trims.fetch(unit["stage"], 0).to_f
          last = units[i + 1].nil? || units[i + 1]["stage"] != unit["stage"]
          last && trim != 0 ? [unit["filter"], "volume=#{format('%g', trim)}dB"] : [unit["filter"]]
        end
        parts.empty? ? nil : parts.join(",")
      end

      # Character presets (voice.yml `character`), all off unless switched on in
      # the file or named by MASTER_TTS_CHARACTER; "none" and "0" force them off.
      def character_names
        presets = data["character"].is_a?(Hash) ? data["character"] : {}
        named = ENV["MASTER_TTS_CHARACTER"].to_s.strip.downcase
        return [] if %w[none 0 off].include?(named)
        return presets.key?(named) ? [named] : [] unless named.empty?

        presets.select { |_name, row| row.is_a?(Hash) && row["enabled"] == true }.keys
      end

      def character_chain
        parts = character_names.map { |name| data["character"][name]["filter"].to_s.strip }.reject(&:empty?)
        parts.empty? ? nil : parts.join(",")
      end

      def fx_payload
        return { enabled: false, units: [] } unless fx_enabled?

        { enabled: true, in_db: fx_config.fetch("in_db", 0), trim_db: fx_config.fetch("trim_db", 0), stage_trim_db: fx_config.fetch("stage_trim_db", {}), ceiling: fx_config.fetch("ceiling", 0.8),
          units: fx_units.map { |unit| unit.slice("id", "stage", "region", "status", "filter") } }
      end

      # Mono to stereo, a short delay on one side for width, reflections as
      # parallel echoes, fixed makeup gain, and the limiter again because the
      # reflections add level above the chain's own ceiling.
      def room_chain
        cfg = room
        return if cfg.empty?

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

      # A top-level voice.yml section, read beside `tts:` so no profile overlays
      # it. Policy is the one reader of voice.yml; other voice code asks here.
      def section(key)
        raw = Master.load_yaml(Master.data_path("voice.yml"), default: {}) || {}
        value = raw[key]
        value.is_a?(Hash) ? value : {}
      end

      # voice.yml `face:`, the one home of how both faces attend and shape the mouth.
      def face_section(key)
        value = section("face")[key]
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

      # What the face reads as MASTER_VOICE_POLICY: which voice speaks, how it
      # is shaped, and the startup sound, so the page sounds like the server.
      def browser_payload = voice_payload.merge(shaping_payload, boot_sound: BootSound.browser_payload)

      def voice_payload
        {
          single_voice: single_voice_key.to_s,
          neural: neural_voice,
          rotation: rotation_keys.map(&:to_s),
          language_voices: language_voices.transform_values(&:to_s),
          language_voice_families: language_voice_families.transform_values { |set| set.transform_values(&:to_s) },
          voices: voice_aliases,

          profile: profile_name,
          persona_affects_text_only: persona_affects_text_only?,
          stream_live_default: stream_live_default?,
          default_rate:,
          default_pitch:,
        }
      end

      def shaping_payload
        {
          post_chain:,
          room:,
          dilla_fx: fx_payload,

          character: character_names.map { |name| { id: name, filter: data["character"][name]["filter"] } },

          awareness:,
          mouth:,
          prosody:,
          layers:,
        }
      end
    end
  end
end
