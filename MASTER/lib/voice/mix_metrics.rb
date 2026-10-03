# frozen_string_literal: true

require "json"
require "open3"

module Master
  module Voice
    # Objective loudness / band levels for council sound & dilla critique payloads.
    # Persona review, multi-solution ideation, and cherry-pick stay in Review::Council.
    module MixMetrics
      module_function

      BANDS = {
        sub_db: [40, 100],
        pad_body_db: [100, 300],
        mids_db: [300, 1200],
        presence_db: [1200, 4000],
        air_db: [4000, 12_000],
      }.freeze

      # Capped, and the cap is reported (analysed_sec, and in the brief) rather
      # than applied silently. One ffmpeg per band over STUDIO/dilla/demo.wav —
      # 47 minutes, 496 MB — was 29s of CPU per critique line, and timed out
      # test_mix_metrics_from_demo_when_present against the suite's 30s budget.
      # One filter_complex pass takes it to 22s; three minutes of it, to 1.3s.
      # A whole set is not a truer sample of band balance, only a costlier one.
      DEFAULT_WINDOW_SEC = 180

      def window_sec
        Integer(ENV.fetch("MASTER_MIX_METRICS_WINDOW_SEC", DEFAULT_WINDOW_SEC.to_s))
      end

      def from_path(path)
        return { error: "missing audio", path: path.to_s } unless path && File.file?(path.to_s)
        return { error: "ffmpeg not installed", path: path.to_s } unless tool?("ffmpeg")

        path = path.to_s
        readings = analyse(path)
        return { error: "ffmpeg analysis failed", path: } unless readings.size == BANDS.size + 1

        overall, *band_readings = readings
        build(path, overall, BANDS.keys.zip(band_readings.map { |r| r[:mean] }).to_h)
      end

      def build(path, overall, bands)
        duration = duration_sec(path)
        {
          path:,
          peak_db: overall[:max],
          rms_db: overall[:mean],
          crest: crest_factor(overall[:max], overall[:mean]),
          duration_sec: duration,
          analysed_sec: duration.positive? ? [duration, window_sec.to_f].min : window_sec.to_f,
          **bands,
          pad_vs_sub_db: (bands[:pad_body_db] && bands[:sub_db] ? (bands[:pad_body_db] - bands[:sub_db]).round(2) : nil),
        }
      end

      def crest_factor(peak_db, rms_db)
        return 0.0 unless peak_db && rms_db && peak_db > -80 && rms_db > -80

        (10**((peak_db - rms_db) / 20.0)).round(3)
      end

      def brief(path)
        m = from_path(path)
        return "mix metrics: #{m[:error]}" if m[:error]

        format(
          "mix metrics (%s, first %.0fs of %.0fs): peak=%.1f dBFS rms=%.1f crest=%.2f " \
          "sub=%.1f pad=%.1f mids=%.1f presence=%.1f air=%.1f pad−sub=%.1f dB",
          File.basename(m[:path].to_s), m[:analysed_sec].to_f, m[:duration_sec].to_f,
          m[:peak_db].to_f, m[:rms_db].to_f, m[:crest].to_f,
          m[:sub_db].to_f, m[:pad_body_db].to_f, m[:mids_db].to_f,
          m[:presence_db].to_f, m[:air_db].to_f, m[:pad_vs_sub_db].to_f
        )
      end

      def default_demo_paths(root = Master::ROOT)
        [
          File.join(Master::REPO_ROOT, "STUDIO/dilla/demo.wav"),
          File.join(root, ".master/media/dilla_beat.mp3"),
          File.join(Dir.pwd, "demo.wav"),
        ]
      end

      def first_existing_demo(root = Master::ROOT)
        default_demo_paths(root).find { |p| File.file?(p) }
      end

      # Overall level plus every band in one decode. Returns
      # [{max:, mean:}, *bands] in graph order, or [] if ffmpeg refused.
      def analyse(path)
        _out, err, status = Open3.capture3(*analysis_command(path))
        return [] unless status.success?

        readings = {}
        # ffmpeg tags each filter instance with its position in the graph
        # (`[Parsed_volumedetect_4 @ 0x…] mean_volume: -31.6 dB`) and prints the
        # summaries in reverse order at teardown, so sort by that index rather
        # than trusting the order of the lines.
        err.scan(/\[Parsed_volumedetect_(\d+)[^\]]*\]\s+(mean|max)_volume:\s*(-?[\d.]+)/) do |index, kind, value|
          (readings[index.to_i] ||= {})[kind.to_sym] = value.to_f
        end
        readings.keys.sort.map { |index| readings[index] }
      end

      def analysis_command(path)
        outlets = (0..BANDS.size).map { |i| "[b#{i}]" }
        chains = ["[b0]volumedetect[o0]"]
        BANDS.each_value.with_index(1) do |(low, high), index|
          chains << "[b#{index}]highpass=f=#{low},lowpass=f=#{high},volumedetect[o#{index}]"
        end
        maps = (0..BANDS.size).flat_map { |i| ["-map", "[o#{i}]", "-f", "null", "-"] }
        [
          "ffmpeg", "-hide_banner", "-nostats", "-t", window_sec.to_s, "-i", path,
          "-filter_complex", "[0:a]asplit=#{outlets.size}#{outlets.join};#{chains.join(';')}",
          *maps
        ]
      end

      def duration_sec(path)
        return 0.0 unless tool?("ffprobe")

        out, = Open3.capture3(
          "ffprobe", "-v", "error", "-show_entries", "format=duration",
          "-of", "default=noprint_wrappers=1:nokey=1", path
        )
        out.to_s.strip.to_f
      end

      # Open3.capture3 raises Errno::ENOENT for a missing binary rather than
      # returning a failed status, so a host without ffmpeg took the whole
      # council critique down instead of degrading.
      def tool?(name)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
          File.executable?(File.join(dir, name))
        end
      end
    end
  end
end
