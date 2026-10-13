# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "timeout"
require "uri"

# Import and inspect the audio stream of a reference. Video frames are never read.
module Dilla
  module Reference
    ROOT = File.expand_path("../../..", __dir__).freeze
    REFERENCE_ROOT = File.join(ENV.fetch("XDG_DATA_HOME", File.expand_path("~/Documents")), "dilla-references").freeze
    MAX_DURATION = 7_200
    DEFAULT_DURATION = 900
    VIDEO_ID = /\A[A-Za-z0-9_-]{11}\z/.freeze
    class Error < StandardError; end
    module_function

    def run(argv)
      options = { stems: true, model: "htdemucs", max_duration: DEFAULT_DURATION, style: "general" }
      OptionParser.new do |parser|
        parser.banner = "Usage: ruby dilla.rb reference YOUTUBE_URL_OR_AUDIO [options]"
        parser.on("--out DIR") { |value| options[:out] = value }
        parser.on("--no-stems") { options[:stems] = false }
        parser.on("--model NAME") { |value| options[:model] = value }
        parser.on("--style NAME") { |value| options[:style] = style_key(value) }
        parser.on("--max-duration SECONDS", Integer) do |value|
          raise OptionParser::InvalidArgument, "duration must be 1..#{MAX_DURATION}" unless value.between?(1, MAX_DURATION)
          options[:max_duration] = value
        end
        parser.on("-h", "--help") { puts parser; return 0 }
      end.parse!(argv)
      source = argv.shift
      raise Error, "provide one YouTube video URL or a local audio file" if source.to_s.empty?
      raise Error, "unexpected arguments: #{argv.join(' ')}" unless argv.empty?
      source.start_with?("http://", "https://") ? download_audio(source, options) : analyze(File.expand_path(source), nil, options)
    rescue OptionParser::ParseError, Error => error
      warn "reference0: #{error.message}"
      2
    rescue StandardError => error
      warn "reference0: failed safely (#{error.class}: #{error.message})"
      1
    end

    def parse_url(value)
      uri = URI.parse(value)
      raise Error, "only direct YouTube URLs are supported" unless %w[http https].include?(uri.scheme)
      host = uri.host.to_s.downcase
      parts = uri.path.to_s.split("/").reject(&:empty?)
      id = if %w[youtu.be www.youtu.be].include?(host)
             parts.first
           elsif %w[youtube.com www.youtube.com m.youtube.com music.youtube.com].include?(host)
             parts == ["watch"] ? URI.decode_www_form(uri.query.to_s).to_h["v"] : (parts[1] if %w[shorts embed live v].include?(parts.first))
           end
      raise Error, "expected a single YouTube video URL" unless VIDEO_ID.match?(id.to_s)
      { id: id, url: "https://www.youtube.com/watch?v=#{id}" }
    rescue URI::InvalidURIError, ArgumentError => error
      raise Error, "invalid YouTube URL: #{error.message}"
    end

    def download_audio(url, options)
      video = parse_url(url)
      ytdlp = executable("YT_DLP_BIN", "yt-dlp") or raise Error, "yt-dlp unavailable"
      out, = capture!("yt-dlp metadata", ytdlp, "--no-playlist", "--skip-download", "--dump-single-json", video[:url])
      metadata = JSON.parse(out)
      seconds = metadata["duration"].to_f
      raise Error, "source exceeds #{options[:max_duration]}s" if seconds.positive? && seconds > options[:max_duration]
      dir = options[:out] ? File.expand_path(options[:out]) : File.join(REFERENCE_ROOT, "#{video[:id]}-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}")
      prepare_dir(dir)
      File.write(File.join(dir, "metadata.json"), JSON.pretty_generate({
        "source_type" => "youtube_audio", "id" => video[:id], "title" => metadata["title"],
        "channel" => metadata["channel"] || metadata["uploader"], "url" => video[:url],
        "duration_seconds" => seconds, "license" => metadata["license"],
        "style_key" => style_key(options[:style])
      }.compact) + "\n")
      capture!("yt-dlp audio-only download", ytdlp, "--no-playlist", "--no-overwrites", "-f", "bestaudio/best",
               "-x", "--audio-format", "wav", "-o", File.join(dir, "source.%(ext)s"), video[:url],
               timeout: [[seconds.ceil + 300, 900].max, 57_600].min)
      audio = File.join(dir, "source.wav")
      raise Error, "download did not produce source.wav" unless File.file?(audio)
      analyze(audio, dir, options)
    end

    def analyze(audio, directory = nil, options = {})
      raise Error, "audio file does not exist: #{audio}" unless File.file?(audio) && File.readable?(audio)
      options = { stems: true, model: "htdemucs", max_duration: DEFAULT_DURATION, style: "general" }.merge(options)
      ffmpeg = executable("FFMPEG_BIN", "ffmpeg") or raise Error, "ffmpeg unavailable"
      ffprobe = executable("FFPROBE_BIN", "ffprobe") or raise Error, "ffprobe unavailable"
      duration = probe_duration(audio, ffprobe)
      raise Error, "source exceeds #{options[:max_duration]}s" if duration && duration > options[:max_duration]
      unless directory
        digest = Digest::SHA256.file(audio).hexdigest[0, 10]
        directory = options[:out] ? File.expand_path(options[:out]) :
          File.join(REFERENCE_ROOT, "#{File.basename(audio, File.extname(audio))}-#{digest}-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}")
        prepare_dir(directory)
      end
      puts "reference0: analyzing audio only"
      mix = metrics(audio, ffmpeg:, ffprobe:, max_duration: options[:max_duration], bands: true)
      stems, separation = separate(audio, directory, options, duration)
      tracks = { "mix" => mix }
      stems.each do |path|
        tracks[File.basename(path, ".wav")] = metrics(path, ffmpeg:, ffprobe:, max_duration: options[:max_duration], bands: false)
      end
      mix["tempo"] = tempo(audio, ffmpeg:, max_duration: options[:max_duration])
      profile = profile_for(mix, style: options[:style]).merge(
        "source_duration_seconds" => mix["duration_seconds"],
        "reference_fingerprint" => Digest::SHA256.file(audio).hexdigest[0, 16]
      ).compact
      File.write(File.join(directory, "profile.json"), JSON.pretty_generate(profile) + "\n")
      FileUtils.mkdir_p(REFERENCE_ROOT)
      File.write(catalog_path(profile), JSON.pretty_generate(profile) + "\n")
      learned = aggregate_saved_profiles(profile.fetch("style_key"), including: profile)
      report = { "schema_version" => 1, "tracks" => tracks, "separation" => separation,
                 "essentia" => essentia(audio, directory), "production_profile" => profile,
                 "learned_profile" => learned,
                 "limitations" => ["Tempo is estimated; half-time and double-time can both fit.",
                                   "Demucs stems can bleed and are not discrete kick/snare/hat multitracks.",
                                   "Spectral levels describe the mix, not isolated instruments.",
                                   "The style label is the user-provided hint, not an automatic genre classification.",
                                   "Only broad production traits guide new music; source audio and composition are not copied."] }
      File.write(File.join(directory, "analysis.json"), JSON.pretty_generate(report) + "\n")
      File.write(File.join(REFERENCE_ROOT, "latest_profile.json"), JSON.pretty_generate(learned) + "\n")
      scoped_profile = profile_path(profile.fetch("style_key"))
      FileUtils.mkdir_p(File.dirname(scoped_profile))
      File.write(scoped_profile, JSON.pretty_generate(learned) + "\n")
      write_active_style(profile.fetch("style_key"))
      write_report(File.join(directory, "report.md"), tracks, separation, profile, learned)
      puts "reference0: style_hint=#{profile.fetch('style_key')}; learned references=#{learned.fetch('reference_count', 1)}; separation=#{separation['status']}; analyzed #{tracks.size - 1} stems"
      puts "reference0: estimated tempo=#{mix.dig('tempo', 'bpm') || 'unknown'} BPM"
      puts "reference0: learned target_bpm=#{learned['target_bpm'] || 'unknown'} groove=#{learned['groove_profile'] || 'unspecified'} features=#{JSON.generate(learned.fetch('features', {}))}"
      puts "reference0: parameters=#{JSON.generate(learned.fetch('parameters', {}))}" unless learned.fetch("parameters", {}).empty?
      puts "reference0: report=#{File.join(directory, 'report.md')}"
      0
    end

    def prepare_dir(path)
      raise Error, "refusing non-empty output directory: #{path}" if Dir.exist?(path) && !Dir.empty?(path)
      FileUtils.mkdir_p(path)
    end

    def metrics(path, ffmpeg:, ffprobe:, max_duration:, bands:)
      out, = capture!("ffprobe", ffprobe, "-v", "error", "-show_format", "-show_streams", "-of", "json", path)
      probe = JSON.parse(out)
      fmt = probe["format"] || {}
      stream = (probe["streams"] || []).find { |row| row["codec_type"] == "audio" } || {}
      _stdout, logs = capture!("FFmpeg audio stats", ffmpeg, "-hide_banner", "-nostats", "-i", path,
                               "-t", max_duration.to_s, "-af", "astats=metadata=0:reset=0,ebur128=peak=true", "-f", "null", "-")
      result = { "duration_seconds" => fmt["duration"]&.to_f, "codec" => stream["codec_name"],
                 "sample_rate_hz" => stream["sample_rate"]&.to_i, "channels" => stream["channels"]&.to_i,
                 "rms_db" => number(logs, /RMS level dB:\s*(-?[\d.]+)/),
                 "peak_db" => number(logs, /Peak level dB:\s*(-?[\d.]+)/),
                 "integrated_lufs" => number(logs, /I:\s*(-?[\d.]+)\s+LUFS/) }.compact
      result["spectral_bands_db"] = band_levels(path, ffmpeg:, max_duration:) if bands
      result
    end

    def band_levels(path, ffmpeg:, max_duration:)
      filters = { "sub_25_120_hz" => "highpass=f=25,lowpass=f=120,volumedetect",
                  "low_mid_120_500_hz" => "highpass=f=120,lowpass=f=500,volumedetect",
                  "mid_500_4000_hz" => "highpass=f=500,lowpass=f=4000,volumedetect",
                  "high_4000_plus_hz" => "highpass=f=4000,volumedetect" }
      filters.to_h do |name, filter|
        _out, logs = capture!("FFmpeg #{name}", ffmpeg, "-hide_banner", "-nostats", "-i", path,
                              "-t", max_duration.to_s, "-af", filter, "-f", "null", "-")
        [name, number(logs, /mean_volume:\s*(-?[\d.]+)\s+dB/)]
      rescue Error
        [name, nil]
      end
    end

    def tempo(path, ffmpeg:, max_duration:)
      bytes, = capture!("tempo envelope", ffmpeg, "-hide_banner", "-v", "error", "-i", path,
                        "-t", max_duration.to_s, "-vn", "-ac", "1", "-af",
                        "aeval=exprs=val(0)*val(0),lowpass=f=12", "-ar", "40", "-f", "f32le", "pipe:1")
      samples = bytes.force_encoding(Encoding::BINARY).unpack("e*")
      return nil if samples.size < 480
      mean = samples.sum / samples.size
      samples.map! { |sample| sample - mean }
      energy = samples.sum { |sample| sample * sample }
      return nil if energy < 1e-12
      score, lag = (12..[40, samples.size / 4].min).map do |candidate|
        total = 0.0
        limit = samples.size - candidate
        index = 0
        while index < limit
          total += samples[index] * samples[index + candidate]
          index += 1
        end
        [total / ([limit, 1].max * energy / samples.size), candidate]
      end.max_by(&:first)
      bpm = 2400.0 / lag
      bpm *= 2 if bpm < 80
      bpm /= 2 if bpm > 175
      { "bpm" => bpm.round(1), "confidence" => score.round(3) }
    rescue Error
      nil
    end

    def separate(audio, directory, options, duration)
      return [[], { "status" => "not_requested", "files" => [] }] unless options[:stems]
      command = executable("DEMUCS_BIN", "demucs")
      return [[], { "status" => "unavailable", "files" => [] }] unless command
      target = File.join(directory, "stems")
      prepare_dir(target)
      _out, logs = capture!("Demucs separation", command, "--name", options[:model], "--out", target, audio,
                            timeout: [[duration.to_f.ceil * 8, 1800].max, 57_600].min)
      files = Dir.glob(File.join(target, "**", "*.wav")).sort
      [files, { "status" => files.empty? ? "no_stems_found" : "separated",
                "model" => options[:model], "files" => files.map { |path| path.delete_prefix(directory + File::SEPARATOR) },
                "log_tail" => logs.lines.last(4).join.strip }]
    rescue Error => error
      [[], { "status" => "failed", "files" => [], "message" => error.message }]
    end

    def essentia(audio, directory)
      exe = executable("ESSENTIA_EXTRACTOR", "streaming_extractor_music")
      return { "status" => "unavailable" } unless exe
      name = File.join(directory, "essentia_features.json")
      capture!("Essentia", exe, audio, name, timeout: 900)
      { "status" => "analyzed", "file" => File.basename(name) }
    rescue Error => error
      { "status" => "failed", "message" => error.message }
    end

    # Normalize only the broad styles MASTER explicitly identifies. The acoustic
    # measurements remain measurements; the style hint is not claimed as detected.
    def style_key(value)
      hint = value.to_s.downcase.tr("_", " ").gsub(/[^a-z0-9]+/, " ").strip
      return "industrial_techno" if hint.match?(/\bindustrial techno\b|\btechno\b/)
      return "j_dilla" if hint.match?(/\bj dilla\b|\bdilla\b|\bboom bap\b|\bhip hop\b/)
      "general"
    end

    def profile_path(style)
      key = style_key(style)
      File.join(REFERENCE_ROOT, "profiles", key, "latest_profile.json")
    end

    def catalog_path(profile)
      key = style_key(profile.fetch("style_key"))
      fingerprint = profile.fetch("reference_fingerprint").to_s
      raise Error, "reference fingerprint must be hexadecimal" unless fingerprint.match?(/\\A[0-9a-f]{16}\\z/i)

      File.join(REFERENCE_ROOT, "records", "#{key}-#{fingerprint.downcase}.json")
    end

    # Keep one compact measurement record per audio source and style. Learned
    # profiles average measurements across references, retaining the newest
    # source duration for planning a take of a suitable length.
    def aggregate_saved_profiles(style, including: nil)
      key = style_key(style)
      paths = Dir.glob(File.join(REFERENCE_ROOT, "records", "#{key}-*.json")).sort
      rows = paths.filter_map { |path| read_profile_record(path, key) }
      if including
        rows.reject! { |row| row["reference_fingerprint"] == including["reference_fingerprint"] }
        rows << including
      end
      aggregate_profiles(key, rows)
    end

    def read_profile_record(path, style)
      value = JSON.parse(File.read(path))
      value if value.is_a?(Hash) && style_key(value["style_key"]) == style
    rescue Errno::ENOENT, JSON::ParserError, TypeError
      nil
    end

    def aggregate_profiles(style, profiles)
      key = style_key(style)
      rows = profiles.select { |row| row.is_a?(Hash) && style_key(row["style_key"]) == key }
                     .uniq { |row| row["reference_fingerprint"] || row.object_id }
      return { "style_key" => key, "genre" => key == "j_dilla" ? "hip_hop" : key,
               "reference_count" => 0 } if rows.empty?

      learned = rows.last.dup
      learned["reference_count"] = rows.size
      learned["reference_fingerprints"] = rows.filter_map { |row| row["reference_fingerprint"] }.uniq
      %w[target_bpm measured_bpm].each do |field|
        average = numeric_mean(rows.filter_map { |row| numeric_value(row[field]) })
        next unless average

        learned[field] = field == "target_bpm" ? average.round : average.round(1)
      end
      %w[features parameters].each do |section|
        keys = rows.flat_map { |row| row.fetch(section, {}).is_a?(Hash) ? row.fetch(section, {}).keys : [] }.uniq
        merged = {}
        keys.each do |field|
          average = numeric_mean(rows.filter_map do |row|
            values = row.fetch(section, {})
            numeric_value(values[field]) if values.is_a?(Hash)
          end)
          merged[field] = average.round(3) if average
        end
        learned[section] = merged unless merged.empty?
      end
      learned
    end

    def numeric_value(value)
      number = Float(value)
      number.finite? ? number : nil
    rescue ArgumentError, TypeError
      nil
    end

    def numeric_mean(values)
      return if values.empty?

      values.sum / values.size
    end

    def active_style_path(root: REFERENCE_ROOT)
      File.join(root, "active_style.json")
    end

    def active_style(root: REFERENCE_ROOT)
      value = JSON.parse(File.read(active_style_path(root:)))
      key = style_key(value["style_key"])
      %w[j_dilla industrial_techno].include?(key) ? key : "general"
    rescue Errno::ENOENT, JSON::ParserError, TypeError, NoMethodError
      "general"
    end

    def write_active_style(style, root: REFERENCE_ROOT)
      key = style_key(style)
      return key unless %w[j_dilla industrial_techno].include?(key)

      FileUtils.mkdir_p(root)
      File.write(active_style_path(root:), JSON.pretty_generate({ "style_key" => key }) + "\n")
      key
    end

    def profile_for(mix, style: "general")
      bands = mix.fetch("spectral_bands_db", {})
      low = ((bands.fetch("sub_25_120_hz", -36.0) - bands.fetch("low_mid_120_500_hz", -36.0) + 8.0) / 24.0).clamp(0.0, 1.0)
      bright = ((bands.fetch("high_4000_plus_hz", -36.0) - bands.fetch("mid_500_4000_hz", -36.0) + 10.0) / 24.0).clamp(0.0, 1.0)
      bpm = mix.dig("tempo", "bpm")&.to_f
      key = style_key(style)
      common = { "style_key" => key, "measured_bpm" => bpm,
                 "tempo_confidence" => mix.dig("tempo", "confidence"), "meter" => "4/4",
                 "features" => { "low_frequency_weight" => low.round(3), "brightness" => bright.round(3) } }
      case key
      when "industrial_techno"
        common.merge("genre" => key, "target_bpm" => bpm ? bpm.clamp(118, 160).round : 138,
          "parameters" => {
            "rumble_level" => (0.09 + 0.10 * low).round(3), "rumble_duck_depth" => (0.70 + 0.20 * low).round(3),
            "hat_probability" => (0.46 + 0.30 * bright).round(3), "metal_probability" => (0.07 + 0.13 * bright).round(3),
            "distortion_drive" => (1.6 + 0.9 * bright).round(2)
          }, "production" => "straight four-on-the-floor; distorted rumble; metallic hits; evolving industrial textures; no hip-hop swing")
      when "j_dilla"
        common.merge("genre" => "hip_hop", "target_bpm" => bpm ? bpm.clamp(70, 110).round : 88,
          "groove_profile" => "behind_the_beat",
          "production" => "sample-led hip-hop reference; laid-back pocket; syncopated boom-bap drums; warm, slightly imperfect texture")
      else
        common.merge("genre" => "general", "target_bpm" => bpm&.round,
          "production" => "use measured tempo, spectral balance, loudness and duration as broad reference cues; do not infer unmeasured groove or instrumentation")
      end
    end

    def write_report(path, tracks, separation, profile, learned = profile)
      lines = ["# Audio reference analysis", "", "Estimated tempo: #{tracks.dig('mix', 'tempo', 'bpm') || 'unknown'} BPM",
               "Style hint: #{profile['style_key']} (provided by the user, not automatically classified)",
               "References in learned profile: #{learned['reference_count'] || 1}",
               "Stem separation: #{separation['status']}", "", "## Parts"]
      tracks.each { |name, row| lines << "- #{name}: #{row['duration_seconds'] || '?'} s; RMS #{row['rms_db'] || 'unknown'} dB" }
      lines.concat(["", "## Frequency bands"])
      tracks.fetch("mix").fetch("spectral_bands_db", {}).each { |name, value| lines << "- #{name}: #{value || 'not measured'} dB" }
      lines.concat(["", "## This reference", JSON.pretty_generate(profile),
                    "", "## Learned style profile", JSON.pretty_generate(learned),
                    "", "Audio only was analyzed. The renderer creates new material and does not use source audio or stems.", ""])
      File.write(path, lines.join("\n"))
    end

    def probe_duration(path, ffprobe)
      out, = capture!("ffprobe duration", ffprobe, "-v", "error", "-show_entries", "format=duration",
                      "-of", "default=noprint_wrappers=1:nokey=1", path)
      Float(out.strip)
    rescue Error, ArgumentError
      nil
    end

    def capture!(label, *command, timeout: 120)
      stdout, stderr, status = Timeout.timeout(timeout) { Open3.capture3(*command) }
      return [stdout, stderr] if status.success?
      raise Error, "#{label} exited #{status.exitstatus}: #{stderr.lines.last(5).join.strip}"
    rescue Errno::ENOENT => error
      raise Error, "#{label}: executable missing (#{error.message})"
    rescue Timeout::Error
      raise Error, "#{label} timed out after #{timeout}s"
    end

    def executable(env, name)
      name = ENV[env].to_s.strip.then { |value| value.empty? ? name : value }
      if name.include?(File::SEPARATOR)
        File.file?(name) && File.executable?(name) ? name : nil
      else
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }
           .find { |path| File.file?(path) && File.executable?(path) }
      end
    end

    def number(text, pattern)
      match = text.match(pattern)
      match && Float(match[1])
    rescue ArgumentError
      nil
    end
  end
end
