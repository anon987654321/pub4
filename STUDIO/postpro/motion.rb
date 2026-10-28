# frozen_string_literal: true

require "open3"
require "json"
require "fileutils"
require "tmpdir"
require "tempfile"

# Video is the same grade as a still, with one Ruby process for the whole
# sequence. Frames cross ffmpeg as raw RGB bytes; libvips grades each frame
# in-process. Only the finished frames are spooled to disk, under a byte cap.
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
    def self.probe(path)
      raise Unavailable, "video input is not a readable file: #{path}" unless File.file?(path)
      raise Unavailable, "ffmpeg and ffprobe are not on PATH" unless available?

      output, status = Open3.capture2e(
        "ffprobe", "-v", "error", "-print_format", "json",
        "-show_streams", "-show_format", path.to_s
      )
      raise Unavailable, "ffprobe could not read #{path}: #{output.lines.last.to_s.strip}" unless status.success?

      document = JSON.parse(output)
      streams = document.fetch("streams", [])
      video = streams.find { |stream| stream["codec_type"] == "video" }
      raise Unavailable, "#{path} carries no video stream" unless video

      nominal_rate = video["r_frame_rate"].to_s
      average_rate = video["avg_frame_rate"].to_s
      nominal_fps = parse_fps(nominal_rate)
      average_fps = parse_fps(average_rate)
      if nominal_fps.positive? && average_fps.positive? && (nominal_fps - average_fps).abs > 0.5
        raise Unavailable, "variable or ambiguous frame rate (#{average_rate} average, #{nominal_rate} nominal); refusing to alter timestamps"
      end

      rate = average_fps.positive? ? average_rate : nominal_rate
      fps = parse_fps(rate)
      duration = document.dig("format", "duration").to_f
      frames = video["nb_frames"].to_s.to_i
      frames = (duration * fps).ceil if frames <= 0 && duration.positive? && fps.positive?
      raise Unavailable, "ffprobe did not report a usable frame count and frame rate" unless frames.positive? && fps.positive?
      width = video["width"].to_i
      height = video["height"].to_i
      raise Unavailable, "video has invalid dimensions #{width}x#{height}" unless width.positive? && height.positive?
      raise Unavailable, "frame is too large (#{width}x#{height})" if width * height > MAX_FRAME_PIXELS

      Probe.new(
        width:, height:, fps:, frames:, duration:,
        has_audio: streams.any? { |stream| stream["codec_type"] == "audio" },
        rate:
      )
    rescue JSON::ParserError => e
      raise Unavailable, "ffprobe returned invalid JSON: #{e.message}"
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

      input = File.realpath(input.to_s)
      target = File.expand_path(output.to_s)
      raise Unavailable, "video output must use .mp4 so its codec/container contract is explicit" unless File.extname(target).downcase == ".mp4"
      raise Unavailable, "refusing to replace the input video" if input == target
      raise Unavailable, "refusing to replace an output symlink" if File.symlink?(target)

      probe = probe(input)
      limits = limits_from_env
      estimate = estimate(probe, seconds_per_frame: limits[:seconds_per_frame])
      raise Unavailable, "estimate #{estimate[:frames]} frames exceeds the #{limits[:max_frames]}-frame budget" if estimate[:frames] > limits[:max_frames]
      total_pixels = probe.width * probe.height * estimate[:frames]
      raise Unavailable, "estimate exceeds the #{limits[:max_pixels]}-pixel processing budget" if total_pixels > limits[:max_pixels]
      raise Unavailable, "estimate #{estimate[:seconds]}s exceeds the #{limits[:max_seconds]}s runtime budget" if estimate[:seconds] > limits[:max_seconds]

      FileUtils.mkdir_p(File.dirname(target))
      started = monotonic
      deadline = started + limits[:max_seconds]
      io.puts "motion: #{probe.width}x#{probe.height} #{probe.rate}fps #{estimate[:frames]} frames" \
              "#{probe.has_audio ? ' + audio' : ''}; estimated #{estimate[:seconds]}s, hard budget #{limits[:max_seconds]}s"

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

        temporary_output = File.join(work, "result.mp4")
        assemble(graded, input, temporary_output, probe, deadline)
        raise Unavailable, "ffmpeg produced no output video" unless File.file?(temporary_output) && File.size(temporary_output).positive?

        File.rename(temporary_output, target)
      end
      io.puts "motion: wrote #{target} frames=#{estimate[:frames]} elapsed=#{(monotonic - started).round(2)}s"
      target
    end

    def self.stream_and_grade(input, probe, graded, deadline, limits, seed, grain, io, grade_frame)
      frame_bytes = probe.width * probe.height * 3
      count = 0
      command = [
        "ffmpeg", "-nostdin", "-v", "error", "-i", input,
        "-map", "0:v:0", "-an", "-sn", "-dn", "-vsync", "0",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"
      ]

      Tempfile.create(["postpro-motion-decode-", ".log"]) do |log|
        pid = nil
        begin
          IO.popen(command, "rb", err: log, pgroup: true) do |pipe|
            pid = pipe.pid
            begin
              loop do
                bytes = read_frame(pipe, frame_bytes, deadline)
                break unless bytes

                count += 1
                raise Unavailable, "decoded frames exceed the #{limits[:max_frames]}-frame budget" if count > limits[:max_frames]
                raise Unavailable, "decoded frames exceed the #{limits[:max_pixels]}-pixel processing budget" if count * probe.width * probe.height > limits[:max_pixels]

                target = File.join(graded, format("%06d.png", count))
                frame_seed = seed_for(count - 1, seed, grain:)
                grade_frame.call(bytes, probe.width, probe.height, target, frame_seed)
                unless File.file?(target) && File.size(target).positive?
                  raise Unavailable, "frame #{count} did not produce a readable output"
                end
                yield target
                io.puts "motion: frame #{count}" if (count % 25).zero?
                raise Unavailable, "video grading exceeded the #{limits[:max_seconds]}s runtime budget" if monotonic > deadline
              end
            rescue StandardError
              terminate_child(pid, group: true)
              raise
            end
          end
          status = $?
        rescue StandardError => e
          raise e if e.is_a?(Unavailable)

          log.rewind
          detail = log.read.lines.last(3).join(" ").strip
          raise Unavailable, "ffmpeg frame decode failed: #{detail.empty? ? e.message : detail}"
        end
        unless status&.success?
          log.rewind
          raise Unavailable, "ffmpeg frame decode failed: #{log.read.lines.last(3).join(' ').strip}"
        end
      end
      count
    end

    def self.read_frame(pipe, frame_bytes, deadline)
      buffer = String.new(capacity: frame_bytes, encoding: Encoding::BINARY)
      while buffer.bytesize < frame_bytes
        remaining = deadline - monotonic
        raise Unavailable, "video grading exceeded its runtime budget while decoding" unless remaining.positive?

        IO.select([pipe], nil, nil, [remaining, 0.25].min)
        chunk = pipe.read_nonblock([frame_bytes - buffer.bytesize, 1_048_576].min, exception: false)
        next if chunk == :wait_readable
        return nil if chunk.nil? && buffer.empty?
        raise Unavailable, "ffmpeg ended in the middle of a frame" if chunk.nil?

        buffer << chunk
      end
      buffer
    rescue Errno::EINTR
      retry
    end

    def self.assemble(graded, source, output, probe, deadline)
      args = [
        "ffmpeg", "-nostdin", "-v", "error", "-y",
        "-framerate", probe.rate, "-i", File.join(graded, "%06d.png")
      ]
      if probe.has_audio
        args.concat(["-i", source, "-map", "0:v:0", "-map", "1:a?", "-c:a", "copy", "-shortest"])
      else
        args.concat(["-map", "0:v:0"])
      end
      args.concat(["-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", "-movflags", "+faststart", output])
      run_command(args, deadline:)
    end

    def self.run_command(args, deadline:)
      Tempfile.create(["postpro-motion-assemble-", ".log"]) do |log|
        pid = Process.spawn(*args, in: File::NULL, out: log, err: [:child, :out], pgroup: true)
        status = nil
        loop do
          waited, candidate = Process.waitpid2(pid, Process::WNOHANG)
          if waited
            status = candidate
            break
          end
          if monotonic >= deadline
            terminate_child(pid, group: true)
            Process.waitpid(pid) rescue nil
            log.rewind
            raise Unavailable, "ffmpeg assembly exceeded its runtime budget: #{log.read.lines.last(3).join(' ').strip}"
          end
          sleep 0.05
        end
        unless status.success?
          log.rewind
          raise Unavailable, "ffmpeg assembly failed: #{log.read.lines.last(3).join(' ').strip}"
        end
      end
    rescue Errno::ENOENT => e
      raise Unavailable, "ffmpeg is unavailable: #{e.message}"
    end

    def self.limits_from_env
      {
        max_frames: integer_setting("POSTPRO_VIDEO_MAX_FRAMES", DEFAULT_MAX_FRAMES, 1, 10_000),
        max_pixels: integer_setting("POSTPRO_VIDEO_MAX_PIXELS", DEFAULT_MAX_PIXELS, 1_000_000, 2_000_000_000),
        max_seconds: integer_setting("POSTPRO_VIDEO_MAX_SECONDS", DEFAULT_MAX_SECONDS, 5, 3_600),
        max_temp_bytes: integer_setting("POSTPRO_VIDEO_MAX_TEMP_BYTES", DEFAULT_MAX_TEMP_BYTES, 16_000_000, 10_000_000_000),
        seconds_per_frame: float_setting("POSTPRO_VIDEO_SECONDS_PER_FRAME", DEFAULT_SECONDS_PER_FRAME, 0.01, 60.0)
      }
    end

    def self.integer_setting(name, default, minimum, maximum)
      value = Integer(ENV.fetch(name, default.to_s), exception: false)
      raise Unavailable, "#{name} must be between #{minimum} and #{maximum}" unless value&.between?(minimum, maximum)

      value
    end

    def self.float_setting(name, default, minimum, maximum)
      value = Float(ENV.fetch(name, default.to_s), exception: false)
      raise Unavailable, "#{name} must be between #{minimum} and #{maximum}" unless value&.between?(minimum, maximum)

      value
    end

    def self.terminate_child(pid, group: false)
      target = group ? -pid : pid
      Process.kill("TERM", target)
      sleep 0.1
      Process.kill("KILL", target)
    rescue Errno::ESRCH
      nil
    end

    def self.monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end

# This wrapper deliberately uses the same in-process chain as a one-shot still.
# Re-entering postpro.rb for every frame was the defect that made the previous
# video attempt roughly an hour per minute of 1080p.
def postpro_video_grade_frame(bytes, width, height, target, preset_name, frame_seed)
  $postpro_seed = frame_seed
  image = Vips::Image.new_from_memory(bytes, width, height, 3, :uchar)
                      .copy(interpretation: :srgb).copy_memory
  processed = preset(image, preset_name)
  processed = apply_finishing_grain(anchor_tones(processed), preset_name)
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
  seed = Integer(ENV.fetch("POSTPRO_SEED", "1"), exception: false) || 1
  Postpro::Motion.grade(source, output, preset: preset_name, seed:, grain:) do |bytes, width, height, target, frame_seed|
    postpro_video_grade_frame(bytes, width, height, target, preset_name, frame_seed)
  end
  0
rescue Postpro::Motion::Unavailable, ArgumentError, IOError => e
  PostproBootstrap.dmesg("ERROR video: #{e.message}")
  1
end
