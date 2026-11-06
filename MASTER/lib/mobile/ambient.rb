# frozen_string_literal: true

require_relative "../io/exec"
require_relative "../ground/personal_permissions"
require "timeout"
require_relative "env"

module Master
  module Mobile
    # Speech in and out through Termux:API. Listening happens only inside
    # listen_once, which the person starts by pressing listen; there is no
    # background capture to switch on, and no audio is stored.
    class Ambient
      Result = Data.define(:ok, :text, :error) do
        def ok? = ok == true
      end

      def initialize(config: Mobile.config, capture: Master::Io::Exec.method(:capture3),
                     speaker: ->(cmd, text) { system(cmd, text) }, permissions: nil, root: Master::ROOT)
        @ambient = config.fetch("ambient", {})
        @capture = capture
        @speaker = speaker
        @permissions = permissions || Master::Ground::PersonalPermissions.new(root:)
        @speaking = Mutex.new
      end

      def listen_once
        if (missing = voice_input_permission_missing)
          return failed(missing)
        end

        command = @ambient["stt"] || "termux-speech-to-text"
        return failed("speech-to-text unavailable: #{command}") unless Env.on_path?(command)

        out, err, status = Timeout.timeout(Integer(@ambient["stt_timeout_s"] || 30)) { @capture.call(command) }
        return Result.new(ok: true, text: out.to_s.strip, error: nil) if status.success?

        failed(err.to_s.strip.empty? ? "speech-to-text failed" : err.to_s.strip)
      rescue Timeout::Error
        failed("speech-to-text timed out")
      end

      # One voice at a time: a second reply waits for the first rather than talking over it.
      def speak!(text)
        text = text.to_s.strip
        return failed("nothing to say") if text.empty?

        command = @ambient["tts"] || "termux-tts-speak"
        return failed("text-to-speech unavailable: #{command}") unless Env.on_path?(command)

        spoken = @speaking.synchronize { @speaker.call(command, text) }
        spoken ? Result.new(ok: true, text:, error: nil) : failed("text-to-speech failed")
      end

      private

      # A browser button is still microphone access. Keep it under the same
      # two default-deny grants as the terminal Face::Ear adapter.
      def voice_input_permission_missing
        unless @permissions.allowed?(
          scope: "microphone",
          purpose: Master::Ground::PersonalPermissions::MICROPHONE_PURPOSE
        )
          return 'microphone consent required: /privacy grant microphone --confirm "GRANT microphone"'
        end
        unless @permissions.allowed?(
          scope: "speech_recognition",
          purpose: Master::Ground::PersonalPermissions::SPEECH_RECOGNITION_PURPOSE
        )
          return 'speech-recognition consent required: /privacy grant speech_recognition --confirm "GRANT speech_recognition"'
        end

        nil
      rescue StandardError => e
        "voice input permission check failed: #{e.class}: #{e.message}"
      end

      def failed(error) = Result.new(ok: false, text: nil, error:)
    end
  end
end
