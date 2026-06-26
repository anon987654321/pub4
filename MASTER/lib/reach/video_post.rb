# frozen_string_literal: true

require "net/http"
require "open3"
require "shellwords"
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
    end
  end
end