# frozen_string_literal: true

require "json"
require "open3"
require "yaml"

module Master
  module Voice
    # Audio-side regression checks. No ML dependency is required: ffprobe/ffmpeg
    # provide stable waveform facts, while optional aubio adds F0 when installed.
    module Benchmark
      CONFIG_PATH = Master.data_path("tts_benchmark.yml")
      DEFAULT_CONFIG = {
        "min_score" => 75,
        "speech_rate_wpm" => { "min" => 105, "max" => 220 },
        "dynamic_range_db" => { "min" => 6 },
        "clipping_peak_db" => { "max" => -0.1 },
        "pause_ms" => { "min" => 70, "max" => 700 },
      }.freeze

      PROMPTS = [
        "Good morning. The answer is simple, but the interesting part comes next.",
        "Wait, really? Yes. That small detail changes everything.",
        "The key is not speed. It is rhythm, contrast, and knowing when to breathe.",
        "I can explain it clearly. First the result, then the reason, and finally the catch.",
        "Be careful here: a technically correct voice can still sound completely lifeless.",
        "Imagine this sentence slowing down just before the reveal. That tiny pause matters.",
        "Now we move from the practical answer to the deeper idea behind it.",
        "Sometimes a short answer should be short. No theatrical pause is needed.",
        "And then, unexpectedly, the voice should lift a little before landing.",
        "The final point is this: consistency should feel human, not mechanical.",
      ].freeze

      module_function

      def config
        raw = File.exist?(CONFIG_PATH) ? YAML.safe_load(File.read(CONFIG_PATH)) : {}
        DEFAULT_CONFIG.merge(raw.is_a?(Hash) ? raw.fetch("benchmark", {}) : {})
      rescue StandardError
        DEFAULT_CONFIG
      end

      def available?
        executable?("ffprobe") && executable?("ffmpeg")
      end

      def analyze(path, words: nil)
        return { path:, available: false } unless available? && File.file?(path)

        duration = probe_duration(path)
        silence = silence_profile(path)
        rms = rms_profile(path)
        result = {
          path:,
          available: true,
          duration_s: duration,
          silence:,
          rms:,
          speech_rate_wpm: speech_rate(words, duration),
          clipped: rms[:peak_db] >= -0.1,
          dynamic_range_db: rms[:peak_db] - rms[:rms_db],
        }

        f0 = aubio_pitch(path)
        result[:f0] = f0 if f0
        result
      end

      def score(metrics, text:)
        checks = []
        checks << [:audio_present, metrics[:duration_s].to_f > 0.25]
        checks << [:not_clipped, !metrics[:clipped]]
        checks << [:dynamic_range, metrics[:dynamic_range_db].to_f >= config.dig("dynamic_range_db", "min").to_f]
        checks << [:rhythm, metrics.dig(:silence, :count).to_i.zero? || metrics.dig(:silence, :mean_ms).to_f.between?(config.dig("pause_ms", "min").to_f, config.dig("pause_ms", "max").to_f)]

        words = text.to_s.split.size
        rate = metrics[:speech_rate_wpm].to_f
        checks << [:speech_rate, rate.zero? || rate.between?(config.dig("speech_rate_wpm", "min").to_f, config.dig("speech_rate_wpm", "max").to_f)]

        passed = checks.count { |_, ok| ok }
        {
          score: ((passed.to_f / checks.length) * 100).round(1),
          checks: checks.to_h,
          passed:,
          total: checks.length,
        }
      end

      def torture_prompts
        PROMPTS
      end

      def probe_duration(path)
        out, _err, status = Open3.capture3(
          "ffprobe", "-v", "error", "-show_entries", "format=duration",
          "-of", "default=noprint_wrappers=1:nokey=1", path
        )
        status.success? ? out.to_f : 0.0
      end

      def silence_profile(path)
        out, err, status = Open3.capture3(
          "ffmpeg", "-hide_banner", "-i", path.to_s, "-af",
          "silencedetect=noise=-42dB:d=0.07", "-f", "null", "-"
        )
        trace = "#{out}\n#{err}"
        return { count: 0, mean_ms: 0.0, max_ms: 0.0 } unless status.success? || !trace.empty?

        durations = trace.scan(/silence_duration:\s*([0-9.]+)/).flatten.map { |v| v.to_f * 1000 }
        {
          count: durations.length,
          mean_ms: durations.empty? ? 0.0 : durations.sum / durations.length,
          max_ms: durations.max.to_f,
        }
      rescue StandardError
        { count: 0, mean_ms: 0.0, max_ms: 0.0 }
      end

      def rms_profile(path)
        out, err, _status = Open3.capture3(
          "ffmpeg", "-hide_banner", "-i", path.to_s,
          "-af", "volumedetect", "-f", "null", "-"
        )
        trace = "#{out}\n#{err}"
        peak = trace[/max_volume:\s*(-?[0-9.]+) dB/, 1].to_f
        rms = trace[/mean_volume:\s*(-?[0-9.]+) dB/, 1].to_f
        { peak_db: peak, rms_db: rms }
      rescue StandardError
        { peak_db: -99.0, rms_db: -99.0 }
      end

      def speech_rate(words, duration)
        return 0.0 unless words.to_i.positive? && duration.to_f.positive?

        words.to_f / duration.to_f * 60.0
      end

      def aubio_pitch(path)
        return unless executable?("aubionotes")

        out, _err, status = Open3.capture3(
          "aubionotes", "-i", path.to_s, "-t", "0.2"
        )
        return unless status.success?

        values = out.lines.filter_map do |line|
          hz = line.split.last.to_f
          hz if hz.between?(50, 500)
        end
        return if values.empty?

        {
          min_hz: values.min.round(1),
          max_hz: values.max.round(1),
          mean_hz: (values.sum / values.length).round(1),
          range_hz: (values.max - values.min).round(1),
        }
      rescue StandardError
        nil
      end

      def executable?(name)
        system("which", name, out: File::NULL, err: File::NULL)
      end
    end
  end
end
