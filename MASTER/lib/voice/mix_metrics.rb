# frozen_string_literal: true

require "json"
require "open3"

module Master
  module Voice
    # Objective loudness / band levels for council sound & dilla critique payloads.
    # Persona review, multi-solution ideation, and cherry-pick stay in Review::Council.
    module MixMetrics
      module_function

      def from_path(path)
        return { error: "missing audio", path: path.to_s } unless path && File.file?(path.to_s)

        path = path.to_s
        peak_db, rms_db = volume_levels(path)
        duration = duration_sec(path)
        crest = if peak_db && rms_db && peak_db > -80 && rms_db > -80
                  (10**((peak_db - rms_db) / 20.0)).round(3)
                else
                  0.0
                end
        sub = band_rms(path, 40, 100)
        pad_body = band_rms(path, 100, 300)
        mids = band_rms(path, 300, 1200)
        presence = band_rms(path, 1200, 4000)
        air = band_rms(path, 4000, 12_000)
        {
          path: path,
          peak_db: peak_db,
          rms_db: rms_db,
          crest: crest,
          duration_sec: duration,
          sub_db: sub,
          pad_body_db: pad_body,
          mids_db: mids,
          presence_db: presence,
          air_db: air,
          pad_vs_sub_db: (pad_body && sub ? (pad_body - sub).round(2) : nil),
        }
      end

      def brief(path)
        m = from_path(path)
        return "mix metrics: #{m[:error]}" if m[:error]

        format(
          "mix metrics (%s): peak=%.1f dBFS rms=%.1f crest=%.2f dur=%.1fs " \
          "sub=%.1f pad=%.1f mids=%.1f presence=%.1f air=%.1f pad−sub=%.1f dB",
          File.basename(m[:path].to_s),
          m[:peak_db].to_f, m[:rms_db].to_f, m[:crest].to_f, m[:duration_sec].to_f,
          m[:sub_db].to_f, m[:pad_body_db].to_f, m[:mids_db].to_f,
          m[:presence_db].to_f, m[:air_db].to_f, m[:pad_vs_sub_db].to_f
        )
      end

      def default_demo_paths(root = Master::ROOT)
        [
          File.join(root, "tools/dilla/demo.wav"),
          File.join(root, ".master/media/dilla_beat.mp3"),
          File.join(Dir.pwd, "demo.wav"),
        ]
      end

      def first_existing_demo(root = Master::ROOT)
        default_demo_paths(root).find { |p| File.file?(p) }
      end

      def volume_levels(path)
        _out, err, status = Open3.capture3(
          "ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "volumedetect", "-f", "null", "-"
        )
        blob = "#{err}#{_out}"
        return [nil, nil] unless status.success?

        peak = blob[/max_volume:\s*([-\d.]+)/, 1]&.to_f
        rms = blob[/mean_volume:\s*([-\d.]+)/, 1]&.to_f
        [peak, rms]
      end

      def duration_sec(path)
        out, = Open3.capture3(
          "ffprobe", "-v", "error", "-show_entries", "format=duration",
          "-of", "default=noprint_wrappers=1:nokey=1", path
        )
        out.to_s.strip.to_f
      end

      # Band mean volume via ffmpeg highpass+lowpass + volumedetect (no wavefile gem).
      def band_rms(path, highpass, lowpass)
        af = "highpass=f=#{highpass},lowpass=f=#{lowpass},volumedetect"
        _out, err, status = Open3.capture3(
          "ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", af, "-f", "null", "-"
        )
        return nil unless status.success?

        blob = "#{err}#{_out}"
        blob[/mean_volume:\s*([-\d.]+)/, 1]&.to_f
      end
    end
  end
end
