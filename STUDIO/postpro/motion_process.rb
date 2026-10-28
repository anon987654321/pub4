# frozen_string_literal: true

require "tempfile"

module Postpro
  module Motion
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
                if count > limits[:max_frames]
                  raise Unavailable, "decoded frames exceed the #{limits[:max_frames]}-frame budget"
                end
                if count * probe.width * probe.height > limits[:max_pixels]
                  raise Unavailable, "decoded frames exceed the #{limits[:max_pixels]}-pixel processing budget"
                end

                target = File.join(graded, format("%06d.png", count))
                frame_seed = seed_for(count - 1, seed, grain:)
                begin
                  grade_frame.call(bytes, probe.width, probe.height, target, frame_seed)
                rescue StandardError => e
                  raise Unavailable, "grading frame #{count} failed: #{e.class}: #{e.message}"
                end
                unless File.file?(target) && File.size(target).positive?
                  raise Unavailable, "frame #{count} did not produce a readable output"
                end
                yield target
                io.puts "motion: frame #{count}" if (count % 25).zero?
                if monotonic > deadline
                  raise Unavailable, "video grading exceeded the #{limits[:max_seconds]}s runtime budget"
                end
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
      args.concat([
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16",
        "-metadata", "creation_time=1970-01-01T00:00:00Z",
        "-movflags", "+faststart", output
      ])
      run_command(args, deadline:)
    end

    def self.verify_constant_rate!(input, probe, deadline:)
      output, status = capture_command(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "frame=best_effort_timestamp_time", "-of", "csv=p=0", input],
        deadline:
      )
      raise Unavailable, "ffprobe could not read video frame timestamps" unless status.success?

      timestamps = output.lines.filter_map { |line| Float(line.strip, exception: false) }
      unless timestamps.length == probe.frames
        raise Unavailable,
              "frame timestamp count #{timestamps.length} differs from metadata count " +
              "#{probe.frames}; refusing ambiguous timing"
      end

      expected = 1.0 / probe.fps
      tolerance = [0.001, expected * 0.02].max
      intervals = timestamps.each_cons(2).map { |a, b| b - a }
      if intervals.any? { |interval| interval <= 0 || (interval - expected).abs > tolerance }
        raise Unavailable, "variable frame timing detected; normalise it explicitly before grading"
      end
      true
    end

    def self.run_command(args, deadline:)
      output, status = capture_command(args, deadline:)
      unless status.success?
        raise Unavailable, "ffmpeg assembly failed: #{output.lines.last(3).join(' ').strip}"
      end

      true
    end

    # A bounded child process whose stdout/stderr land in a temp log, not an
    # unbounded pipe or a shell. Used for ffprobe output and the final mux.
    def self.capture_command(args, deadline:)
      Tempfile.create(["postpro-motion-command-", ".log"]) do |log|
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
            raise Unavailable,
                  "#{File.basename(args.first)} exceeded the video runtime budget: " \
                  "#{log.read.lines.last(3).join(' ').strip}"
          end
          sleep 0.05
        end
        log.rewind
        [log.read, status]
      end
    rescue Errno::ENOENT => e
      raise Unavailable, "#{File.basename(args.first)} is unavailable: #{e.message}"
    end

    def self.limits_from_env
      {
        max_frames: integer_setting("POSTPRO_VIDEO_MAX_FRAMES", DEFAULT_MAX_FRAMES, 1, 10_000),
        max_pixels: integer_setting("POSTPRO_VIDEO_MAX_PIXELS", DEFAULT_MAX_PIXELS, 1_000_000, 2_000_000_000),
        max_seconds: integer_setting("POSTPRO_VIDEO_MAX_SECONDS", DEFAULT_MAX_SECONDS, 5, 3_600),
        max_temp_bytes: integer_setting(
          "POSTPRO_VIDEO_MAX_TEMP_BYTES", DEFAULT_MAX_TEMP_BYTES, 16_000_000, 10_000_000_000
        ),
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
