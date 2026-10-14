# frozen_string_literal: true

require "fileutils"
require "open3"
require "yaml"

module Dilla
  # Offline MP4 export. The waveform is drawn over an architectural grid and
  # the canonical Postpro video recipe adds the shared film treatment.
  module Video
    class Error < StandardError; end

    WIDTH = 1280
    HEIGHT = 720
    FPS = 30
    VIDEO_RECIPE = File.expand_path("../../../postpro/video.yml", __dir__).freeze
    FILTER_VALUE = /\A[a-zA-Z0-9_=@.,: +()\/'-]+\z/.freeze

    module_function

    # Never overwrite an old take just because the operator typed the short command.
    # Prefer the familiar filenames when absent; otherwise keep the prior audio intact
    # and render into ignored out/, adding a timestamp only when that pair is occupied.
    def default_paths(root:, output_dir: ENV["DILLA_OUTPUT_DIR"], stamp: Time.now.utc.strftime("%Y%m%dT%H%M%SZ"))
      base = File.expand_path(output_dir.to_s.empty? ? root : output_dir)
      [
        { audio: File.join(base, "dilla.wav"), video: File.join(base, "dilla.mp4") },
        { audio: File.join(base, "out", "dilla.wav"), video: File.join(base, "out", "dilla.mp4") },
      ].each do |pair|
        return pair.freeze unless pair.values.any? { |path| occupied?(path) }
      end

      index = 0
      loop do
        suffix = index.zero? ? stamp : "#{stamp}-#{index}"
        pair = {
          audio: File.join(base, "out", "dilla-#{suffix}.wav"),
          video: File.join(base, "out", "dilla-#{suffix}.mp4"),
        }
        return pair.freeze unless pair.values.any? { |path| occupied?(path) }

        index += 1
      end
    end

    def paired_path(audio)
      path = File.expand_path(audio.to_s)
      return path.sub(/\.(?:wav|wave)\z/i, ".mp4") if path.match?(/\.(?:wav|wave)\z/i)

      "#{path}.mp4"
    end

    def available? = !executable("ffmpeg").nil?

    def encoder_available?
      binary = executable("ffmpeg")
      return false unless binary

      stdout, _stderr, status = Open3.capture3(binary, "-hide_banner", "-encoders")
      status.success? && stdout.include?("libx264")
    rescue StandardError
      false
    end

    def render(audio:, output:, preset: "dilla_heavy", replace: false)
      source = File.expand_path(audio.to_s)
      target = File.expand_path(output.to_s)
      raise Error, "WAV source is missing or empty: #{source}" unless File.file?(source) && File.size(source).positive?
      raise Error, "refusing to overwrite existing MP4 #{target}" if occupied?(target) && !replace

      binary = executable("ffmpeg")
      raise Error, "ffmpeg unavailable; WAV is safe, MP4 was not produced" unless binary

      filters = postpro_filters(preset)
      FileUtils.mkdir_p(File.dirname(target))
      temporary = File.join(
        File.dirname(target),
        ".#{File.basename(target, ".mp4")}.#{Process.pid}.#{Thread.current.object_id}.tmp.mp4",
      )
      command = [
        binary, "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
        "-i", source,
        "-filter_complex", filter_graph(filters),
        "-map", "[v]", "-map", "0:a:0",
        "-c:v", "libx264", "-preset", "medium", "-crf", "19",
        "-pix_fmt", "yuv420p", "-r", FPS.to_s,
        "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart",
        "-shortest", temporary,
      ]
      _stdout, stderr, status = Open3.capture3(*command)
      unless status.success? && File.file?(temporary) && File.size(temporary).positive?
        detail = stderr.to_s.lines.last(5).join.strip
        raise Error, "ffmpeg exit=#{status.exitstatus}: #{detail.empty? ? "no diagnostic output" : detail}"
      end

      # link() is atomic and refuses an occupied destination. Replacing an existing
      # take is possible only when the operator explicitly passed --replace.
      if replace
        File.rename(temporary, target)
      else
        File.link(temporary, target)
        File.delete(temporary)
      end
      puts format("studio0: wrote %s (1280x720, %d fps, %s)", target, FPS, preset)
      target
    rescue Error
      raise
    rescue StandardError => e
      raise Error, "#{e.class}: #{e.message}"
    ensure
      begin
        File.delete(temporary) if temporary && File.exist?(temporary)
      rescue SystemCallError
        nil
      end
    end

    def postpro_filters(preset)
      return [] if ENV["DILLA_VIDEO_POSTPRO"] == "0"

      data = YAML.safe_load(File.read(VIDEO_RECIPE), permitted_classes: [], aliases: false)
      filters = data.fetch("presets").fetch(preset.to_s) do
        raise Error, "unknown video preset #{preset.inspect} in #{VIDEO_RECIPE}"
      end.fetch("filters")
      filters.map do |value|
        filter = value.to_s
        raise Error, "unsafe character in Postpro filter #{filter.inspect}" unless FILTER_VALUE.match?(filter)

        # FFmpeg's filter-graph grammar requires quoting the space-separated tmix weights.
        filter.gsub(/weights=([0-9]+(?:\s+[0-9]+)+)/) { "weights='#{$1}'" }
      end
    rescue KeyError => e
      raise Error, "video recipe is incomplete: #{e.message}"
    end

    def filter_graph(postpro = [])
      background = [
        "color=c=0x07101b:s=#{WIDTH}x#{HEIGHT}:r=#{FPS}",
        "drawgrid=width=80:height=80:thickness=1:color=0x203b56@0.55",
        "drawbox=x=52:y=48:w=1176:h=624:color=0x7298bd@0.65:t=1",
        "drawbox=x=116:y=108:w=1048:h=504:color=0x203b56@0.95:t=1",
        "[base]",
      ].join(",")
      wave = "[0:a]showwaves=s=#{WIDTH}x390:mode=cline:rate=#{FPS}:colors=0x8de1ff," \
             "format=rgba,colorkey=black:0.05:0.02[wave]"
      composite = "[base][wave]overlay=0:165:shortest=1:format=auto"
      composite += ",#{postpro.join(",")}" unless postpro.empty?
      "#{background};#{wave};#{composite},format=yuv420p[v]"
    end

    def occupied?(path) = File.exist?(path) || File.symlink?(path)

    def executable(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |directory|
        path = File.join(directory, name)
        return path if File.file?(path) && File.executable?(path)
      end
      nil
    end
    private_class_method :occupied?, :executable
  end
end
