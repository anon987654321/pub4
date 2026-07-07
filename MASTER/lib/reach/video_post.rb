# frozen_string_literal: true

require "fileutils"
require "net/http"
require "open3"
require "securerandom"
require "uri"

module Master
  module Reach
    # FFmpeg helpers for VideoChain — Open3 only, no curl/system.
    module VideoPost
      module_function

      def apply_analog_filter(input_path, grain:, vignette:)
        output_path = input_path.sub(/\.mp4\z/, "_analog.mp4")
        filter = "noise=alls=#{grain}:allf=t+u,vignette=#{vignette}"
        run_ffmpeg(%W[-y -i #{input_path} -vf #{filter} -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p #{output_path}])
        output_path
      end

      def apply_cinematic_grade(input_path, output_path:, preset:, duration: nil, fps: 24, width: 1920, height: 1080)
        filter = cinematic_filter(preset: preset, fps: fps, width: width, height: height)
        argv = %W[-y -i #{input_path}]
        argv += %W[-t #{duration.round(2)}] if duration.to_f.positive?
        argv += %W[-vf #{filter} -r #{fps} -c:v libx264 -preset slow -crf 17 -pix_fmt yuv420p -movflags +faststart #{output_path}]
        run_ffmpeg(argv)
        output_path
      end

      def cinematic_filter(preset:, fps: 24, width: 1920, height: 1080)
        look = grade_look(preset)
        [
          "scale=#{width}:#{height}:force_original_aspect_ratio=decrease",
          "pad=#{width}:#{height}:(ow-iw)/2:(oh-ih)/2",
          "fps=#{fps}",
          "eq=contrast=#{look[:contrast]}:saturation=#{look[:saturation]}:brightness=#{look[:brightness]}:gamma=#{look[:gamma]}",
          "curves=#{look[:curves]}",
          "unsharp=5:5:0.35:3:3:0.12",
          "noise=alls=#{look[:grain]}:allf=t+u",
          "vignette=#{look[:vignette]}",
          "format=yuv420p",
        ].join(",")
      end

      def grade_look(preset)
        {
          "commercial" => { contrast: 1.08, saturation: 1.10, brightness: 0.01, gamma: 0.98, curves: "medium_contrast", grain: 6, vignette: "PI/7" },
          "infomercial" => { contrast: 1.04, saturation: 1.14, brightness: 0.015, gamma: 0.98, curves: "lighter", grain: 4, vignette: "PI/9" },
          "beauty" => { contrast: 1.03, saturation: 1.04, brightness: 0.01, gamma: 1.02, curves: "lighter", grain: 8, vignette: "PI/8" },
          "analog" => { contrast: 1.10, saturation: 0.98, brightness: 0.0, gamma: 1.0, curves: "medium_contrast", grain: 14, vignette: "PI/5" },
          "cinematic" => { contrast: 1.12, saturation: 1.02, brightness: -0.005, gamma: 0.97, curves: "strong_contrast", grain: 10, vignette: "PI/6" },
        }.fetch(preset.to_s) do
          { contrast: 1.08, saturation: 1.05, brightness: 0.0, gamma: 1.0, curves: "medium_contrast", grain: 8, vignette: "PI/7" }
        end
      end

      def concat_clips(clip_list, output_path)
        list_file = File.join(Dir.tmpdir, "video_chain_concat_#{SecureRandom.hex(6)}.txt")
        File.write(list_file, clip_list.map { |path| "file '#{File.expand_path(path)}'" }.join("\n"))
        run_ffmpeg(%W[-y -f concat -safe 0 -i #{list_file} -c copy #{output_path}])
        File.delete(list_file)
        output_path
      end

      def download_url(url, path)
        uri = URI(url)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 120) do |http|
          res = http.get(uri.request_uri)
          raise "download failed #{res.code}" unless res.code.to_i.between?(200, 299)

          File.binwrite(path, res.body)
        end
        path
      end

      def run_ffmpeg(argv)
        cmd = ["ffmpeg", *argv]
        _out, err, status = Master::Reach::Exec.capture3(*cmd)
        raise "ffmpeg failed: #{err.to_s.lines.last.to_s.strip}" unless status.success?

        true
      end

      def probe_duration(video_path)
        out, err, status = Master::Reach::Exec.capture3(
          "ffprobe", "-v", "error", "-show_entries", "format=duration",
          "-of", "default=noprint_wrappers=1:nokey=1", video_path
        )
        raise "ffprobe failed: #{err.to_s.strip}" unless status.success?

        out.to_f
      end

      def extract_keyframes(video_path, output_dir, count: 8)
        FileUtils.mkdir_p(output_dir)
        duration = probe_duration(video_path)
        samples = [count, 1].max
        max_time = [duration - 0.05, 0].max
        keyframes = []
        samples.times do |index|
          time = if samples == 1
            0.0
          else
            (index.to_f / (samples - 1)) * max_time
          end
          out = File.join(output_dir, format("keyframe_%03d.jpg", index))
          run_ffmpeg(%W[-y -ss #{time.round(2)} -i #{video_path} -vframes 1 -update 1 -q:v 2 #{out}])
          keyframes << out if File.exist?(out)
        end
        keyframes
      end

      # Split every video frame to individual JPEGs (Replicate LoRA input). Scales down past 1440px.
      def extract_all_frames(video_path, output_dir, max_dimension: 1440)
        FileUtils.mkdir_p(output_dir)
        pattern = File.join(output_dir, "frame_%06d.jpg")
        scale = "scale='min(#{max_dimension},iw)':-2"
        run_ffmpeg(%W[-y -i #{video_path} -vf #{scale} -vsync 0 -q:v 2 #{pattern}])
        Dir.glob(File.join(output_dir, "frame_*.jpg"))
          .select { |path| File.file?(path) && File.size(path) > 10_000 }
          .sort
      end
    end
  end
end
