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
        _out, err, status = Open3.capture3(*cmd)
        raise "ffmpeg failed: #{err.to_s.lines.last.to_s.strip}" unless status.success?

        true
      end

      def probe_duration(video_path)
        out, err, status = Open3.capture3(
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