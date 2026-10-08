# frozen_string_literal: true

require "open3"

module Master
  module Device
    # Android audio boundary. Higher layers decide what to say; this module
    # decides how a Termux device emits or plays it.
    module Audio
      TTS_COMMAND = "termux-tts-speak"
      MEDIA_PLAYER = "termux-media-player"
      STREAM = "MUSIC"

      module_function

      def available?
        return false unless Device.android?

        tts_available? || media_player_available?
      end

      def tts_available?
        Device.android? && executable?(TTS_COMMAND)
      end

      def media_player_available?
        Device.android? && executable?(MEDIA_PLAYER)
      end

      def speak(text, stream: STREAM)
        return false if text.to_s.strip.empty?
        return false unless tts_available?

        run(TTS_COMMAND, "-s", stream.to_s, text.to_s)
      end

      def play(path)
        return false unless media_player_available?
        return false unless File.file?(path) && File.size?(path)

        run(MEDIA_PLAYER, "play", path)
      end

      def stop
        return false unless media_player_available?

        run(MEDIA_PLAYER, "stop")
      end

      def status
        {
          tts: tts_available?,
          media_player: media_player_available?,
        }
      end

      def executable?(command)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
          path = File.join(dir, command)
          File.file?(path) && File.executable?(path)
        end
      end

      def run(*argv)
        _stdout, _stderr, status = Open3.capture3(*argv)
        status.success?
      rescue StandardError
        false
      end
    end
  end
end
