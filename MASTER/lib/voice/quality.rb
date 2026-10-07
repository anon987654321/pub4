# frozen_string_literal: true

require "open3"

module Master
  module Voice
    module Quality
      module_function

      def inspect(path)
        return { ok: false, reason: :missing } unless path && File.size?(path)

        duration, sample_rate, channels = probe(path)
        return { ok: false, reason: :unreadable } unless duration && sample_rate && channels

        {
          ok: duration.positive? && duration <= 180.0,
          duration_s: duration.round(3),
          sample_rate: sample_rate,
          channels: channels,
          clipping: clipping?(path),
        }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Voice::Quality.inspect")
        { ok: false, reason: :error }
      end

      def probe(path)
        out, _err, status = Open3.capture3(
          "ffprobe", "-v", "error", "-select_streams", "a:0",
          "-show_entries", "format=duration:stream=sample_rate,channels",
          "-of", "csv=p=0:s=,", path
        )
        return unless status.success?

        values = out.to_s.lines.map(&:strip).reject(&:empty?)
        duration = values.find { |value| value.match?(/\A\d+(?:\.\d+)?\z/) }&.to_f
        integers = values.select { |value| value.match?(/\A\d+\z/) }.map(&:to_i)
        [duration, integers.max, integers.min]
      rescue StandardError
        nil
      end

      def clipping?(path)
        _out, err, status = Open3.capture3(
          "ffmpeg", "-v", "info", "-i", path,
          "-af", "astats=metadata=1:reset=1",
          "-f", "null", "-"
        )
        return false unless status.success?

        err.to_s.downcase.include?("clipping")
      rescue StandardError
        false
      end
    end
  end
end
