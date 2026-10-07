# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "yaml"
require_relative "performance"
require_relative "quality"

module Master
  module Voice
    # Transcendent orchestrator — emotion, melody, multi-engine chain.
    module Transcendent
      DEFAULTS = {
        "personality" => "warm_supportive",
        "engine_chain" => "mlx,chatterbox,edge_melodic,edge,say",
        "emotion_enabled" => true,
        "melodic_enabled" => true,
        "melodic_threshold" => 0.40,
        "phrase_rhythm_enabled" => true,
        "phrase_language_switching" => true,
        "mlx_model" => "mlx-community/chatterbox-fp16",
        "mlx_voice" => "default",
        "exaggeration" => 0.45,
        "cfg_weight" => 0.42,
        "chatterbox_device" => "mps",
        "reference_clip" => "",
      }.freeze

      module_function

      def enabled?
        load_config.fetch("enabled", false)
      end

      def load_config
        path = Master.data_path("tts.yml")
        raw = File.exist?(path) ? YAML.safe_load(File.read(path), permitted_classes: [Symbol]) : {}
        section = raw.is_a?(Hash) ? (raw["transcendent"] || raw[:transcendent] || {}) : {}
        cfg = DEFAULTS.merge(stringify_keys(section))
        default_chain = Engines.openbsd? ? %w[chatterbox mlx edge_melodic edge say].join(",") : cfg["engine_chain"]
        cfg["engine_chain"] = ENV.fetch("MASTER_TTS_ENGINE_CHAIN", default_chain)
        cfg["reference_clip"] = ENV["MASTER_TTS_REFERENCE_CLIP"].to_s.strip unless ENV["MASTER_TTS_REFERENCE_CLIP"].to_s.strip.empty?
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
        return if clean.empty?

        emotion = Emotion.analyze(clean)
        melody = Melody.plan(clean, emotion, melodic: melodic_contour?(cfg, emotion), languages: phrase_languages(cfg))
        resolved_voice, resolved_rate, resolved_pitch = resolve_voice_and_prosody(
          clean, cfg, voice:, style:, rate:, pitch:, voice_locked:, style_locked:
        )
        melody = apply_spoken_performance(
          melody, clean, emotion, style, base_rate: resolved_rate, base_pitch: resolved_pitch
        )

        out_path = "/tmp/m_tts_#{SecureRandom.hex(8)}.mp3"
        played = synthesize_via_chain(clean, cfg, emotion, melody, resolved_voice, resolved_rate, resolved_pitch, out_path)
        return unless played && File.size?(out_path)

        out_path
      end

      def apply_spoken_performance(melody, clean, emotion, style, base_rate:, base_pitch:)
        performance = Performance.apply(
          base_rate:,
          base_pitch:,
          text: clean,
          emotion:,
          style:,
        )
        phrases = melody[:phrases].each_with_index.map do |phrase, index|
          variation = performance[index] || {}
          rate = if melody[:melodic]
                   blend_melodic_rate(phrase[:rate], variation[:rate], base_rate)
                 else
                   variation[:rate] || phrase[:rate]
                 end
          pitch = if melody[:melodic]
                    blend_melodic_pitch(phrase[:pitch], variation[:pitch], base_pitch)
                  else
                    variation[:pitch] || phrase[:pitch]
                  end

          phrase.merge(
            rate:,
            pitch:,
            pause_ms: variation[:pause_ms] || phrase[:pause_ms],
            performance_role: variation[:role],
            emphasis: variation[:emphasis],
          )
        end
        melody.merge(phrases:)
      end

      def blend_melodic_rate(melodic_rate, performance_rate, base_rate)
        return melodic_rate || performance_rate if melodic_rate.to_s.empty?
        return melodic_rate if performance_rate.to_s.empty?

        melodic = melodic_rate.to_s.delete("%").to_i
        performance = performance_rate.to_s.delete("%").to_i
        base = base_rate.to_s.delete("%").to_i
        format("%+d%%", (melodic + performance - base).clamp(-12, 12))
      end

      def blend_melodic_pitch(melodic_pitch, performance_pitch, base_pitch)
        return melodic_pitch || performance_pitch if melodic_pitch.to_s.empty?
        return melodic_pitch if performance_pitch.to_s.empty?

        melodic = melodic_pitch.to_s.delete("Hz").to_i
        performance = performance_pitch.to_s.delete("Hz").to_i
        base = base_pitch.to_s.delete("Hz").to_i
        format("%+dHz", (melodic + performance - base).clamp(-24, 24))
      end

      def synthesize_via_chain(clean, cfg, emotion, melody, resolved_voice, resolved_rate, resolved_pitch, out_path)
        chain = build_engine_chain(cfg, emotion, clean)
        played, used_engine = try_engine_chain(
          chain, clean, cfg, emotion, melody, resolved_voice, resolved_rate, resolved_pitch, out_path
        )
        played || Engines.synth_say(clean, out_path, voice: resolved_voice, rate: resolved_rate)
        log_quality(out_path)
      end

      def resolve_voice_and_prosody(clean, cfg, voice:, style:, rate:, pitch:, voice_locked:, style_locked:)
        resolved_voice = if Language.detect(clean) != :en
                           Speech.voice_for_text(clean)
                         else
                           voice || Speech.default_voice
                         end
        resolved_rate = rate
        resolved_pitch = pitch
        personality = cfg["personality"].to_s

        if personality == "warm_supportive" && style != :fixed
          resolved_rate ||= supportive_rate(clean, style, cfg)
          resolved_pitch ||= supportive_pitch(clean, style, cfg)
        elsif personality == "warm_erratic" && style != :fixed
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

      def supportive_rate(clean, style, cfg)
        words = clean.split.length
        base = case style.to_sym
               when :calm then -7
               when :intimate then -6
               when :storyteller then -5
               when :question then -3
               when :energetic then -1
               else words > 28 ? -6 : -5
               end
        warmth = cfg["warmth"].to_f.clamp(0.0, 1.0)
        depth = cfg["depth"].to_f.clamp(0.0, 1.0)
        delta = ((warmth - 0.5) * -2.0 + (depth - 0.5) * -1.0).round
        format("%+d%%", (base + delta).clamp(-10, 2))
      end

      def supportive_pitch(clean, style, cfg)
        words = clean.split.length
        base = case style.to_sym
               when :calm then -20
               when :intimate then -18
               when :storyteller then -14
               when :question then -8
               when :energetic then -3
               else words > 28 ? -16 : -14
               end
        depth = cfg["depth"].to_f.clamp(0.0, 1.0)
        delta = ((depth - 0.5) * 14.0).round
        format("%+dHz", (base - delta).clamp(-28, 4))
      end

      def warm_erratic_prosody(voice, clean, style, voice_locked, style_locked, resolved_voice)
        locked_style = style_locked ? style : nil
        if voice
          pick = WarmErratic.pick_for_voice(voice, clean, style: locked_style)
        else
          pick = WarmErratic.pick(clean)
          resolved_voice = pick[:voice]
        end
        [resolved_voice, pick[:rate], pick[:pitch]]
      end

      def melodic_contour?(cfg, emotion)
        return false unless cfg["emotion_enabled"] && cfg["melodic_enabled"]

        emotion.dig(:scores, :lyrical).to_f >= cfg["melodic_threshold"].to_f ||
          emotion[:mode].to_sym == :melodic
      end

      def phrase_rendered?(cfg, emotion)
        melodic_contour?(cfg, emotion) || cfg["phrase_rhythm_enabled"] == true
      end

      def phrase_languages(cfg)
        return unless cfg["phrase_language_switching"] == true

        Policy.language_voice_families.each_key.each_with_object({}) do |language, voices|
          voices[language.to_sym] = Policy.voice_for_language(language)
        end
      end

      def build_engine_chain(cfg, emotion, clean)
        chain = cfg["engine_chain"].to_s.split(",").map(&:strip).reject(&:empty?)
        chain = chain.reject { |engine| engine == "edge_melodic" } unless phrase_rendered?(cfg, emotion)
        chain = chain.reject { |engine| %w[mlx chatterbox].include?(engine) } unless cfg["emotion_enabled"]
        language = Language.detect(clean)
        chain.reject { |engine| %w[mlx chatterbox].include?(engine) && language != :en }
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

      def log_quality(path)
        quality = Quality.inspect(path)
        target = File.join(Master::ROOT, ".master", "tts_last.json")
        return unless File.file?(target)

        payload = JSON.parse(File.read(target), symbolize_names: true)
        payload[:quality] = quality
        File.write(target, JSON.generate(payload))
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Transcendent.log_quality")
        nil
      end

      def last_pick
        path = File.join(Master::ROOT, ".master", "tts_last.json")
        return unless File.file?(path)

        JSON.parse(File.read(path), symbolize_names: true)
      rescue JSON::ParserError, SystemCallError
        nil
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
            blend: emotion[:blend],
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
        File.delete(path) if path && File.exist?(path)
      end
    end
  end
end
