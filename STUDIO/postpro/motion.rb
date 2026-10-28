# frozen_string_literal: true

require "open3"
require "json"
require "fileutils"
require "tmpdir"
require "tempfile"
require "digest"
require "time"

# Video is the same grade as a still, with one Ruby process for the whole
# sequence. Frames cross ffmpeg as raw RGB bytes; libvips grades each frame
# in-process. Only the finished frames are spooled to disk, under a byte cap.
#
# This is for the short clips returned by the image tools, not a feature-film
# transcode. Do not substitute an ffmpeg filter look: the film curves, halation
# and stock-specific grain would become a second source of truth and drift from
# stills. Temporal grain is explicit: moving derives a seed from base + frame
# index; held grain uses the base seed. Both modes are deterministic.
module Postpro
  module Motion
    class Unavailable < StandardError; end

    Probe = Struct.new(:width, :height, :fps, :frames, :duration, :has_audio, :rate, keyword_init: true)

    MAX_FRAME_PIXELS = 33_554_432
    DEFAULT_MAX_FRAMES = 600
    DEFAULT_MAX_PIXELS = 500_000_000
    DEFAULT_MAX_SECONDS = 300
    DEFAULT_MAX_TEMP_BYTES = 1_000_000_000
    DEFAULT_SECONDS_PER_FRAME = 1.0

    def self.available?
      system("ffmpeg", "-version", out: File::NULL, err: File::NULL) &&
        system("ffprobe", "-version", out: File::NULL, err: File::NULL)
    end

    # Use stream metadata, not the filename. VFR is refused because converting
    # it to a constant-rate image sequence would silently alter frame timing.
    def self.probe(path, deadline: nil)
      deadline ||= monotonic + 30
      raise Unavailable, "video input is not a readable file: #{path}" unless File.file?(path)
      raise Unavailable, "ffmpeg and ffprobe are not on PATH" unless available?

      output, status = capture_command(
        ["ffprobe", "-v", "error", "-print_format", "json",
         "-show_streams", "-show_format", path.to_s],
        deadline:
      )
      raise Unavailable, "ffprobe could not read #{path}: #{output.lines.last.to_s.strip}" unless status.success?

      document = JSON.parse(output)
      streams = document.fetch("streams", [])
      video = streams.find { |stream| stream["codec_type"] == "video" }
      raise Unavailable, "#{path} carries no video stream" unless video

      nominal_rate = video["r_frame_rate"].to_s
      average_rate = video["avg_frame_rate"].to_s
      # Nominal and average rates can differ for legitimate constant-rate streams.
      # Actual presentation timestamps below are the authority for variable timing.
      rate = parse_fps(average_rate).positive? ? average_rate : nominal_rate
      fps = parse_fps(rate)
      stream_duration = video["duration"].to_f
      format_duration = document.dig("format", "duration").to_f
      duration = stream_duration.positive? ? stream_duration : format_duration
      if rotated_stream?(video)
        raise Unavailable,
              "video has display rotation metadata; normalise orientation before grading so frame dimensions remain stable"
      end
      frames = video["nb_frames"].to_s.to_i
      frames = (duration * fps).ceil if frames <= 0 && duration.positive? && fps.positive?
      unless frames.positive? && fps.positive?
        raise Unavailable, "ffprobe did not report a usable frame count and frame rate"
      end
      width = video["width"].to_i
      height = video["height"].to_i
      raise Unavailable, "video has invalid dimensions #{width}x#{height}" unless width.positive? && height.positive?
      raise Unavailable, "frame is too large (#{width}x#{height})" if width * height > MAX_FRAME_PIXELS
      if width.odd? || height.odd?
        raise Unavailable,
              "MP4 yuv420p output requires even dimensions (#{width}x#{height}); resize explicitly before grading"
      end

      Probe.new(
        width:, height:, fps:, frames:, duration:,
        has_audio: streams.any? { |stream| stream["codec_type"] == "audio" },
        rate:
      )
    rescue JSON::ParserError => e
      raise Unavailable, "ffprobe returned invalid JSON: #{e.message}"
    end

    def self.rotated_stream?(stream)
      values = [stream.dig("tags", "rotate")]
      values.concat(
        Array(stream["side_data_list"]).select { |item| item["side_data_type"].to_s.match?(/display matrix/i) }
                                       .map { |item| item["rotation"] }
      )
      values.compact.filter_map { |value| Float(value, exception: false) }.any? do |degrees|
        remainder = degrees.abs % 360
        remainder > 0.01 && (360 - remainder) > 0.01
      end
    end

    # Keep rational rates exact: 24000/1001 is not 24, and accumulating that
    # difference over a long clip creates visible drift.
    def self.parse_fps(rate)
      return 0.0 if rate.to_s.empty?

      numerator, denominator = rate.split("/", 2).map(&:to_f)
      return numerator if denominator.nil?
      return 0.0 if denominator.zero?

      numerator / denominator
    end

    def self.estimate(probe, seconds_per_frame: DEFAULT_SECONDS_PER_FRAME)
      frames = probe.frames.positive? ? probe.frames : (probe.duration * probe.fps).ceil
      { frames:, seconds: (frames * seconds_per_frame).ceil }
    end

    # Moving grain behaves like different silver crystals on each exposure, but
    # the seed is a pure function of frame number, so the same clip is repeatable.
    # Held grain is a deliberate scanned-print / fixed-texture alternative.
    def self.seed_for(frame_index, base_seed, grain: :moving)
      case grain
      when :moving then base_seed + frame_index
      when :hold then base_seed
      else raise ArgumentError, "grain must be :moving or :hold"
      end
    end

    def self.grade(input, output, preset:, seed: 1, grain: :moving, io: $stdout, &grade_frame)
      raise ArgumentError, "a frame-grading block is required" unless grade_frame
      raise Unavailable, "grain must be :moving or :hold" unless %i[moving hold].include?(grain.to_sym)

      raise Unavailable, "video input is not a readable file: #{input}" unless File.file?(input.to_s)

      input = File.realpath(input.to_s)
      target = File.expand_path(output.to_s)
      grain = grain.to_sym
      unless File.extname(target).downcase == ".mp4"
        raise Unavailable, "video output must use .mp4 so its codec/container contract is explicit"
      end
      raise Unavailable, "refusing to replace the input video" if input == target
      raise Unavailable, "refusing to replace an output symlink" if File.symlink?(target)
      sidecar = "#{target}.json"
      if [target, sidecar].any? { |path| File.exist?(path) || File.symlink?(path) }
        raise Unavailable, "refusing to replace an existing video or sidecar; choose a new output path"
      end

      limits = limits_from_env
      started = monotonic
      deadline = started + limits[:max_seconds]
      probe = probe(input, deadline:)
      estimate = estimate(probe, seconds_per_frame: limits[:seconds_per_frame])
      if estimate[:frames] > limits[:max_frames]
        raise Unavailable, "estimate #{estimate[:frames]} frames exceeds the #{limits[:max_frames]}-frame budget"
      end
      total_pixels = probe.width * probe.height * estimate[:frames]
      if total_pixels > limits[:max_pixels]
        raise Unavailable, "estimate exceeds the #{limits[:max_pixels]}-pixel processing budget"
      end
      if estimate[:seconds] > limits[:max_seconds]
        raise Unavailable, "estimate #{estimate[:seconds]}s exceeds the #{limits[:max_seconds]}s runtime budget"
      end

      verify_constant_rate!(input, probe, deadline:, max_frames: limits[:max_frames])
      FileUtils.mkdir_p(File.dirname(target))
      io.puts "motion: #{probe.width}x#{probe.height} #{probe.rate}fps #{estimate[:frames]} frames" \
              "#{probe.has_audio ? ' + audio' : ''}; estimated #{estimate[:seconds]}s, " \
              "runtime cap #{limits[:max_seconds]}s"
      io.puts "motion: seed=#{seed} grain=#{grain}"

      frames_written = 0

      Dir.mktmpdir(".postpro-motion-", File.dirname(target)) do |work|
        graded = File.join(work, "graded")
        FileUtils.mkdir_p(graded)
        temporary_bytes = 0
        frames_written = stream_and_grade(
          input, probe, graded, deadline, limits, seed, grain, io, grade_frame
        ) do |frame_path|
          temporary_bytes += File.size(frame_path)
          if temporary_bytes > limits[:max_temp_bytes]
            raise Unavailable, "graded frames exceed the #{limits[:max_temp_bytes]}-byte temporary-storage budget"
          end
        end
        raise Unavailable, "ffmpeg produced no video frames" if frames_written.zero?
        if frames_written != estimate[:frames]
          raise Unavailable,
                "metadata estimated #{estimate[:frames]} frames but ffmpeg decoded #{frames_written}; refusing to alter timing"
        end

        temporary_output = File.join(work, "result.mp4")
        assemble(graded, input, temporary_output, probe, deadline)
        unless File.file?(temporary_output) && File.size(temporary_output).positive?
          raise Unavailable, "ffmpeg produced no output video"
        end

        temporary_sidecar = File.join(work, "result.mp4.json")
        metadata = {
          format: 1,
          tool: "postpro",
          source: { basename: File.basename(input), sha256: Digest::SHA256.file(input).hexdigest },
          output: { basename: File.basename(target), sha256: Digest::SHA256.file(temporary_output).hexdigest },
          grade: { preset: preset.to_s, seed: seed, grain: grain.to_s },
          grade_version: GRADE_VERSION,
          video: {
            width: probe.width, height: probe.height, frame_rate: probe.rate,
            frame_count: frames_written, duration_seconds: probe.duration,
            audio_copied: probe.has_audio, codec: "libx264", pixel_format: "yuv420p"
          },
          runtime: {
            estimate_seconds: estimate[:seconds], elapsed_seconds: (monotonic - started).round(3),
            limit_seconds: limits[:max_seconds], graded_frame_bytes: temporary_bytes,
            temp_byte_limit: limits[:max_temp_bytes]
          },
          created_at: Time.now.utc.iso8601
        }
        File.open(temporary_sidecar, "wb") do |file|
          file.write(JSON.pretty_generate(metadata))
          file.write("\n")
          file.flush
          file.fsync
        end
        raise Unavailable, "video grading exceeded its runtime budget before publication" if monotonic > deadline

        # The work directory is a sibling of the destination, so links are
        # atomic and cannot silently replace a path that appeared during grading.
        published_video = false
        begin
          File.link(temporary_output, target)
          published_video = true
          File.link(temporary_sidecar, sidecar)
        rescue SystemCallError => e
          FileUtils.rm_f(target) if published_video
          raise Unavailable, "could not publish output without replacing another file: #{e.message}"
        rescue StandardError
          FileUtils.rm_f(target) if published_video
          raise
        end
      end
      io.puts "motion: wrote #{target} frames=#{frames_written} elapsed=#{(monotonic - started).round(2)}s"
      target
    end


  end
end

require_relative "motion_process"


# This wrapper deliberately uses the same in-process chain as a one-shot still.
# Re-entering postpro.rb for every frame was the defect that made the previous
# video attempt roughly an hour per minute of 1080p.
def postpro_video_grade_frame(bytes, width, height, target, preset_name, frame_seed)
  $postpro_seed = frame_seed
  image = Vips::Image.new_from_memory(bytes, width, height, 3, :uchar)
                      .copy(interpretation: :srgb).copy_memory
  processed = preset(image, preset_name)
  processed = anchor_tones(processed)
  processed = apply_finishing_grain(processed, preset_name, grained: nil)
  rgb_bands(processed).write_to_file(target, compression: 6)
end

def postpro_video_mode
  source = argv_flag("--video")
  output = argv_flag("--output")
  preset_name = (argv_flag("--preset") || "portrait").to_sym
  unless source && File.file?(source)
    PostproBootstrap.dmesg("ERROR --video needs a readable input file")
    return 2
  end
  unless output && !output.start_with?("--")
    PostproBootstrap.dmesg("ERROR --video needs --output FILE.mp4")
    return 2
  end
  unless PRESETS.key?(preset_name)
    PostproBootstrap.dmesg("ERROR --video unknown preset #{preset_name.inspect}; valid: #{PRESETS.keys.join(', ')}")
    return 2
  end

  Postpro::Constitution.verify_distinct_source!(input_path: source, output_path: output)
  grain = ARGV.include?("--grain-hold") ? :hold : :moving
  seed = Integer(ENV.fetch("POSTPRO_SEED", "0"), exception: false) || 0
  Postpro::Motion.grade(
    source, output, preset: preset_name, seed:, grain:
  ) do |bytes, width, height, target, frame_seed|
    postpro_video_grade_frame(
      bytes, width, height, target, preset_name, frame_seed
    )
  end
  0
rescue Postpro::Motion::Unavailable, ArgumentError, IOError, SystemCallError => e
  PostproBootstrap.dmesg("ERROR video: #{e.message}")
  1
end
