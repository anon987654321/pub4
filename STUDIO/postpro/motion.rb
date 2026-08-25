# frozen_string_literal: true

require "open3"
require "json"
require "fileutils"
require "rbconfig"
require "tmpdir"

# postpro on video, frame by frame.
#
# postpro is libvips and every input glob is jpg/jpeg/png/webp, so "the house
# filter on all our photos and videos" was half true. This is the other half:
# ffprobe reads the stream, ffmpeg decodes to frames, the existing grade runs on
# each one unchanged, and ffmpeg reassembles with the original audio.
#
# Frame by frame rather than an ffmpeg filter chain on purpose. The grade is
# 57 presets of film emulation built over libvips — H&D curves, halation,
# per-stock grain, reciprocity — and reimplementing any of it as ffmpeg filters
# would create a second source of truth that drifts from the first. A video
# graded here and a still graded there have to be the same look, and the only
# way to be sure of that is for it to be the same code.
#
# The cost is real and stated rather than discovered: this decodes to disk, so
# a minute of 24fps 1080p is 1440 files, and the grade takes roughly as long per
# frame as it does per photograph. It is not for a feature film. It is for the
# clips that come out of the image tools.
#
# THE TEMPORAL PROBLEM, which is the whole difficulty and not an afterthought.
# Grain that is re-randomised per frame boils — it is the classic tell of a
# filter applied to video by someone who was thinking about stills. postpro
# seeds its grain from POSTPRO_SEED, so passing the same seed for every frame
# holds the grain still. That is correct for grain-as-texture and wrong for
# grain-as-film, because real film grain moves. Both are offered; neither is
# guessed at.
module Postpro
  module Motion
    POSTPRO = File.expand_path("postpro.rb", __dir__)

    class Unavailable < StandardError; end

    Probe = Struct.new(:width, :height, :fps, :frames, :duration, :has_audio, keyword_init: true)

    def self.available?
      system("ffmpeg", "-version", out: File::NULL, err: File::NULL) &&
        system("ffprobe", "-version", out: File::NULL, err: File::NULL)
    end

    # What the file actually is, from ffprobe rather than from its extension.
    def self.probe(path)
      raise Unavailable, "ffmpeg and ffprobe are not on PATH" unless available?

      out, status = Open3.capture2e("ffprobe", "-v", "quiet", "-print_format", "json",
                                    "-show_streams", "-show_format", path.to_s)
      raise Unavailable, "ffprobe could not read #{path}" unless status.success?

      doc = JSON.parse(out)
      video = doc.fetch("streams", []).find { |s| s["codec_type"] == "video" }
      raise Unavailable, "#{path} carries no video stream" unless video

      Probe.new(
        width: video["width"], height: video["height"],
        fps: parse_fps(video["r_frame_rate"]),
        frames: video["nb_frames"].to_i,
        duration: doc.dig("format", "duration").to_f,
        has_audio: doc.fetch("streams", []).any? { |s| s["codec_type"] == "audio" }
      )
    end

    # "24000/1001" is 23.976, and reading it as an integer loses the pulldown
    # every telecined source carries.
    def self.parse_fps(rate)
      return 0.0 if rate.to_s.empty?

      num, den = rate.split("/").map(&:to_f)
      den.nil? || den.zero? ? num : num / den
    end

    # Roughly what this will cost, before it is spent. A minute of 1080p is
    # about 1440 frames, and knowing that up front is the difference between
    # a considered run and an abandoned one.
    def self.estimate(probe, seconds_per_frame: 0.25)
      frames = probe.frames.positive? ? probe.frames : (probe.duration * probe.fps).round
      { frames: frames, seconds: (frames * seconds_per_frame).round }
    end

    # Whether the grain should hold still between frames.
    #
    #   :hold    one seed for every frame. The grain is a fixed texture, which
    #            reads as a dirty lens or a scanned print rather than as film.
    #   :moving  a seed per frame. Real film grain is a different silver
    #            crystal each exposure, so it moves — but it must move
    #            DETERMINISTICALLY, or two runs of the same clip differ and
    #            nothing can be compared. Derived from the base seed and the
    #            frame index, never from rand.
    def self.seed_for(frame_index, base_seed, grain: :moving)
      grain == :hold ? base_seed : base_seed + frame_index
    end
    # Decode, grade, reassemble.
    #
    # Audio is copied from the source rather than re-encoded: this tool has no
    # opinion about sound and re-encoding would lose a generation for nothing.
    # If the source has no audio track the output has none either, instead of
    # silence, which is a different thing.
    def self.grade(input, output, preset:, seed: 1, grain: :moving, workdir: nil, io: $stdout)
      probe = probe(input)
      Dir.mktmpdir do |scratch|
        dir = workdir || scratch
        frames = File.join(dir, "frames")
        graded = File.join(dir, "graded")
        FileUtils.mkdir_p(frames)
        FileUtils.mkdir_p(graded)

        io.puts "motion: #{probe.width}x#{probe.height} #{probe.fps.round(3)}fps " \
                "#{probe.frames} frames#{probe.has_audio ? ' + audio' : ''}"
        run!("ffmpeg", "-nostdin", "-v", "error", "-i", input.to_s,
             File.join(frames, "%06d.png"))

        list = Dir.glob(File.join(frames, "*.png")).sort
        raise Unavailable, "ffmpeg produced no frames from #{input}" if list.empty?

        list.each_with_index do |frame, index|
          target = File.join(graded, File.basename(frame))
          _out, status = Open3.capture2e(
            { "POSTPRO_SEED" => seed_for(index, seed, grain: grain).to_s, "DILLA_QUIET" => "1" },
            RbConfig.ruby, POSTPRO, "--input", frame, "--output", target, "--preset", preset.to_s
          )
          raise Unavailable, "the grade failed on frame #{index + 1}" unless status.success?

          io.puts "motion: frame #{index + 1}/#{list.length}" if ((index + 1) % 25).zero?
        end

        assemble(graded, input, output, probe)
        io.puts "motion: wrote #{output}"
        output
      end
    end

    def self.assemble(graded, source, output, probe)
      args = ["ffmpeg", "-nostdin", "-v", "error", "-y",
              "-framerate", probe.fps.to_s, "-i", File.join(graded, "%06d.png")]
      # -shortest so a copied audio track cannot run past the last graded frame.
      args += ["-i", source.to_s, "-map", "0:v", "-map", "1:a", "-c:a", "copy", "-shortest"] if probe.has_audio
      args += ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", output.to_s]
      run!(*args)
    end

    def self.run!(*args)
      out, status = Open3.capture2e(*args)
      raise Unavailable, "#{args.first} failed: #{out.lines.last(2).join(' ').strip}" unless status.success?

      true
    end
  end
end
