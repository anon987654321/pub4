# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "yaml"

module Master
  module Voice
    # Transcendent orchestrator — emotion, melody, multi-engine chain.
    module Transcendent
      DEFAULTS = {
        "personality" => "warm_erratic",
        "engine_chain" => "mlx,chatterbox,edge_melodic,edge,say",
        "emotion_enabled" => true,
        "melodic_enabled" => true,
        "melodic_threshold" => 0.45,
        "max_chars" => 900,
        "mlx_model" => "mlx-community/chatterbox-fp16",
        "mlx_voice" => "default",
        "exaggeration" => 0.62,
        "cfg_weight" => 0.42,
        "chatterbox_device" => "mps",
        "reference_clip" => ""
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
        DEFAULTS.merge(stringify_keys(section))
      rescue StandardError
        DEFAULTS.dup
      end

      def stringify_keys(hash)
        hash.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }
      end

      def synthesize(text, voice: nil, style: :auto, rate: nil, pitch: nil, voice_locked: false, style_locked: false)
        cfg = load_config
        clean = Speech.clean_text(text)
        return if clean.empty? || clean.length < 20

        emotion = Emotion.analyze(clean)
        melody = Melody.plan(clean, emotion)

        resolved_voice = voice || Speech.default_voice
        resolved_rate = rate
        resolved_pitch = pitch
        personality = cfg["personality"].to_s

        if personality == "warm_erratic" && style != :fixed
          locked_style = style_locked ? style : nil
          if voice_locked && voice
            pick = WarmErratic.pick_for_voice(voice, clean, style: locked_style)
          else
            pick = WarmErratic.pick(clean)
            resolved_voice = pick[:voice]
          end
          resolved_rate ||= pick[:rate]
          resolved_pitch ||= pick[:pitch]
        elsif style != :auto && Speech::STYLES.key?(style.to_sym)
          sc = Speech.style_config_for(resolved_voice, style)
          resolved_rate ||= sc[:rate]
          resolved_pitch ||= sc[:pitch]
        end

        resolved_rate ||= "-5%"
        resolved_pitch ||= "-18Hz"

        out_path = "/tmp/m_tts_#{SecureRandom.hex(8)}.mp3"
        chain = cfg["engine_chain"].to_s.split(",").map(&:strip).reject(&:empty?)
        melodic_on = cfg["emotion_enabled"] && cfg["melodic_enabled"]
        melodic_on &&= emotion.dig(:scores, :lyrical).to_f >= cfg["melodic_threshold"].to_f
        chain = chain.reject { |e| e == "edge_melodic" } unless melodic_on
        chain = chain.reject { |e| %w[mlx chatterbox].include?(e) } unless cfg["emotion_enabled"]

        played = false
        used_engine = nil
        chain.each do |engine|
          next unless Engines.available?(engine, cfg)

          played = Engines.synth(
            engine,
            text: clean,
            out_path: out_path,
            cfg: cfg,
            emotion: emotion,
            melody: melody,
            voice: Speech.resolve_voice(resolved_voice),
            rate: resolved_rate.to_s,
            pitch: resolved_pitch.to_s
          )
          if played
            used_engine = engine
            break
          end
        end

        log_pick(used_engine, resolved_voice, resolved_rate, resolved_pitch, emotion)

        unless played
          played = Engines.synth_say(clean, out_path)
        end

        return unless played && File.size?(out_path)

        out_path
      end

      def log_pick(engine, voice, rate, pitch, emotion)
        path = File.join(Master::ROOT, ".master", "tts_last.json")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(
          path,
          JSON.generate(
            engine: engine,
            voice: voice,
            rate: rate,
            pitch: pitch,
            primary: emotion[:primary],
            at: Time.now.to_i
          )
        )
      rescue StandardError
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