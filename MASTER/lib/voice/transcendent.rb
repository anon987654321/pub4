# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "yaml"

module Master
  module Voice
    # Transcendent orchestrator — emotion, melody, multi-engine chain.
    module Transcendent
      MIN_SYNTHESIZABLE_CHARS = 20
      DEFAULTS = {
        "personality" => "warm_erratic",
        "engine_chain" => "mlx,chatterbox,edge_melodic,edge,say",
        "emotion_enabled" => true,
        "melodic_enabled" => true,
        "melodic_threshold" => 0.45,
        # Phrase segmentation and inter-phrase rests, without the pentatonic
        # contour. Separate from melodic_* because it is rhythm rather than
        # style: melodic_threshold kept the whole phrase plan for lyrical text
        # only, so every ordinary reply was one Edge call at one rate and one
        # pitch. The cost is one Edge round trip per phrase, bounded by
        # Melody::MAX_PHRASES; set false to go back to a single call.
        "phrase_rhythm_enabled" => true,
        # Read a Norwegian clause with a Norwegian voice instead of putting it
        # through ms-MY-OsmanNeural. Off, because data/voice.yml sets
        # single_voice: osman and persona_affects_text_only: true — one voice is
        # a recorded decision, and this is the one thing that would break it.
        # The machinery is here so the choice is a flag rather than a rewrite.
        "phrase_language_switching" => false,
        "phrase_language_voices" => { "nb" => "finn", "en" => nil },
        "max_chars" => 900,
        "mlx_model" => "mlx-community/chatterbox-fp16",
        "mlx_voice" => "default",
        "exaggeration" => 0.62,
        "cfg_weight" => 0.42,
        "chatterbox_device" => "mps",
        "reference_clip" => "",
      }.freeze

      module_function

      def enabled?
        cfg = load_config
        cfg.fetch("enabled", false)
      end

      def load_config
        path = Master.data_path("tts.yml")
        raw = File.exist?(path) ? YAML.safe_load(File.read(path), permitted_classes: [Symbol]) : {}
        section = raw.is_a?(Hash) ? (raw["transcendent"] || raw[:transcendent] || {}) : {}
        cfg = DEFAULTS.merge(stringify_keys(section))
        if Engines.openbsd?
          cfg["engine_chain"] = ENV.fetch("MASTER_TTS_ENGINE_CHAIN", Engines::OPENBSD_CHAIN.join(","))
        end
        cfg
      rescue StandardError
        DEFAULTS.dup
      end

      def stringify_keys(hash)
        hash.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }
      end

      def synthesize(text, voice: nil, style: :auto, rate: nil, pitch: nil, voice_locked: false, style_locked: false)
        cfg = load_config
        clean = Speech.clean_text(text)
        return if clean.empty? || clean.length < MIN_SYNTHESIZABLE_CHARS

        emotion = Emotion.analyze(clean)
        melody = Melody.plan(clean, emotion, melodic: melodic_contour?(cfg, emotion), languages: phrase_languages(cfg))
        resolved_voice, resolved_rate, resolved_pitch = resolve_voice_and_prosody(
          clean, cfg, voice:, style:, rate:, pitch:, voice_locked:, style_locked:
        )

        out_path = "/tmp/m_tts_#{SecureRandom.hex(8)}.mp3"
        played = synthesize_via_chain(clean, cfg, emotion, melody, resolved_voice, resolved_rate, resolved_pitch, out_path)
        return unless played && File.size?(out_path)

        out_path
      end

      def synthesize_via_chain(clean, cfg, emotion, melody, resolved_voice, resolved_rate, resolved_pitch, out_path)
        chain = build_engine_chain(cfg, emotion)
        played, used_engine = try_engine_chain(
          chain, clean, cfg, emotion, melody, resolved_voice, resolved_rate, resolved_pitch, out_path
        )
        log_pick(used_engine, resolved_voice, resolved_rate, resolved_pitch, emotion)
        played || Engines.synth_say(clean, out_path)
      end

      def resolve_voice_and_prosody(clean, cfg, voice:, style:, rate:, pitch:, voice_locked:, style_locked:)
        resolved_voice = voice || Speech.default_voice
        resolved_rate = rate
        resolved_pitch = pitch
        personality = cfg["personality"].to_s

        if personality == "warm_erratic" && style != :fixed
          resolved_voice, wr_rate, wr_pitch = warm_erratic_prosody(voice, clean, style, voice_locked, style_locked, resolved_voice)
          resolved_rate ||= wr_rate
          resolved_pitch ||= wr_pitch
        elsif style != :auto && Speech::STYLES.key?(style.to_sym)
          sc = Speech.style_config_for(resolved_voice, style)
          resolved_rate ||= sc[:rate]
          resolved_pitch ||= sc[:pitch]
        end

        resolved_rate ||= "-5%"
        resolved_pitch ||= "-18Hz"
        [resolved_voice, resolved_rate, resolved_pitch]
      end

      def warm_erratic_prosody(voice, clean, style, voice_locked, style_locked, resolved_voice)
        locked_style = style_locked ? style : nil
        if voice_locked && voice
          pick = WarmErratic.pick_for_voice(voice, clean, style: locked_style)
        else
          pick = WarmErratic.pick(clean)
          resolved_voice = pick[:voice]
        end
        [resolved_voice, pick[:rate], pick[:pitch]]
      end

      # The pentatonic contour. Lyrical text only — this is the stylistic mode.
      def melodic_contour?(cfg, emotion)
        return false unless cfg["emotion_enabled"] && cfg["melodic_enabled"]

        emotion.dig(:scores, :lyrical).to_f >= cfg["melodic_threshold"].to_f
      end

      # Whether to render phrase by phrase at all. Either the contour wants it or
      # phrase rhythm does; the engine is the same, the plan differs.
      def phrase_rendered?(cfg, emotion)
        melodic_contour?(cfg, emotion) || cfg["phrase_rhythm_enabled"] == true
      end

      # nil when switching is off, so Melody attaches no :voice at all and every
      # phrase inherits the single locked voice.
      def phrase_languages(cfg)
        return nil unless cfg["phrase_language_switching"] == true

        voices = cfg["phrase_language_voices"]
        return nil unless voices.is_a?(Hash)

        voices.filter_map { |lang, key| [lang.to_s.to_sym, key.to_s.to_sym] if key.to_s != "" }.to_h
      end

      def build_engine_chain(cfg, emotion)
        chain = cfg["engine_chain"].to_s.split(",").map(&:strip).reject(&:empty?)
        chain = chain.reject { |e| e == "edge_melodic" } unless phrase_rendered?(cfg, emotion)
        chain = chain.reject { |e| %w[mlx chatterbox].include?(e) } unless cfg["emotion_enabled"]
        chain
      end

      def try_engine_chain(chain, clean, cfg, emotion, melody, resolved_voice, resolved_rate, resolved_pitch, out_path)
        played = false
        used_engine = nil
        chain.each do |engine|
          next unless Engines.attempt?(engine, cfg)

          played = attempt_engine(engine, clean, cfg, emotion, melody, resolved_voice, resolved_rate, resolved_pitch, out_path)
          if played
            used_engine = engine
            break
          end
        end
        [played, used_engine]
      end

      def attempt_engine(engine, clean, cfg, emotion, melody, resolved_voice, resolved_rate, resolved_pitch, out_path)
        Engines.synth(
          engine,
          text: clean,
          out_path:,
          cfg:,
          emotion:,
          melody:,
          voice: Speech.resolve_voice(resolved_voice),
          rate: resolved_rate.to_s,
          pitch: resolved_pitch.to_s,
        )
      end

      def log_pick(engine, voice, rate, pitch, emotion)
        path = File.join(Master::ROOT, ".master", "tts_last.json")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(
          path,
          JSON.generate(
            engine:,
            voice:,
            rate:,
            pitch:,
            primary: emotion[:primary],
            at: Time.now.to_i,
          ),
        )
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Transcendent.log_pick")
        nil
      end

      def synthesize_bytes(text, **opts)
        path = synthesize(text, **opts)
        return unless path

        File.binread(path)
      ensure
        File.unlink(path) if path && File.exist?(path)
      end
    end
  end
end
