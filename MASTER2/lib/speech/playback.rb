# frozen_string_literal: true

module MASTER
  module Speech
    # Playback - audio file playback and download
    module Playback
      module_function

      # Download audio from URL and play it
      def download_and_play(url, temp_file)
        require "net/http"
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        response = http.get(uri.request_uri)
        File.binwrite(temp_file, response.body)
        play_audio(temp_file)
        FileUtils.rm_f(temp_file)
      end

      # Play an audio file
      def play_audio(file)
        return unless file && File.exist?(file)

        case RUBY_PLATFORM
        when /openbsd/
          system("aucat -i #{file} 2>/dev/null") || system("mpv --no-video #{file} 2>/dev/null")
        when /darwin/
          system("afplay #{file}")
        when /linux/
          system("mpv --no-video --really-quiet #{file} 2>/dev/null") ||
            system("aplay -q #{file} 2>/dev/null") ||
            system("paplay #{file} 2>/dev/null")
        when /mingw|mswin|cygwin/
          system("powershell -c \"(New-Object Media.SoundPlayer '#{file}').PlaySync()\"")
        end
      end
    end
  end
end
