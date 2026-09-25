# frozen_string_literal: true

require "tmpdir"

module Master
  module CLI
    module Face
      # The face's microphone. On Android, Termux:API's termux-speech-to-text
      # is the recogniser. On a host with sox, a take ends on silence and
      # Gemini transcribes that file. The words then go through the session,
      # which is what the next turn remembers. A typed line is the fallback.
      #
      # Without it the ear says what is missing and hears nothing. A typed
      # line is the fallback; a guessed transcription never is.
      class Ear
        HINT = "install the Termux:API app, then pkg install termux-api"
        SOX = %w[sox -q -d -r 16000 -c 1].freeze
        # A quiet room is well under one percent of full scale, so the old
        # gate never opened and the file stayed empty. Speech starts the take;
        # a short quiet, or the caller, ends it.
        SILENCE = %w[silence 1 0.05 0.05% 1 0.8 0.08%].freeze
        MAX_TAKE_S = 12

        def initialize(device: Master::Device)
          @device = device
        end

        # Nil when the ear can listen, otherwise the sentence that says why not.
        def missing
          return termux_missing if @device.android?
          return "mic0: sox missing — type instead" unless sox?

          nil
        end

        def available? = missing.nil?

        # Listens until stop answers true or the recogniser ends on silence,
        # handing each partial match to on_partial as it arrives. Returns the
        # last match, which is the fullest, or nil when nothing was heard.
        def listen(stop:, on_partial: nil)
          return termux_listen(stop:, on_partial:) if @device.android?

          host_listen(stop:, on_partial:)
        end

        private

        def termux_missing
          return nil if Master::Voice::Playback.which("termux-speech-to-text")

          "mic0: termux-speech-to-text missing — #{HINT}; type instead"
        end

        def sox?
          system("command", "-v", "sox", out: File::NULL, err: File::NULL)
        end

        def termux_listen(stop:, on_partial:)
          stdout, wait_thr = @device.speech_to_text_start
          heard = []
          reader = Thread.new { read_matches(stdout, heard, on_partial) }
          sleep 0.05 while wait_thr.alive? && !stop.call
          halt(wait_thr)
          reader.join(1)
          heard.last
        ensure
          stdout&.close unless stdout&.closed?
        end

        # sox ends the take on silence. The words are the transcription of
        # that file, not a guess, and the reply itself still goes through the
        # session so the next turn can hear this one.
        def host_listen(stop:, on_partial:)
          wav = File.join(Dir.tmpdir, "master-face-#{Process.pid}.wav")
          File.delete(wav) if File.exist?(wav)
          pid = Process.spawn(*SOX, wav, *SILENCE, out: File::NULL, err: File::NULL)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          sleep 0.05 while alive?(pid) && !stop.call && (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) < MAX_TAKE_S
          finish_sox(pid)
          return unless File.size?(wav).to_i > 2_000

          text = transcribe(wav)
          on_partial&.call(text) if text && !text.empty?
          text
        ensure
          File.delete(wav) if wav && File.exist?(wav)
        end

        def alive?(pid)
          Process.kill(0, pid)
          true
        rescue Errno::ESRCH
          false
        end

        def finish_sox(pid)
          Process.kill("INT", pid) if alive?(pid)
          Process.wait(pid)
        rescue Errno::ESRCH, Errno::ECHILD
          nil
        end

        def transcribe(wav)
          key = gemini_key
          return unless key

          require "net/http"
          require "json"
          require "base64"
          uri = URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=#{key}")
          body = {
            contents: [{ parts: [
              { text: 'Transcribe the speech. Reply as JSON: {"heard":"..."} . Empty heard when there is no speech.' },
              { inline_data: { mime_type: "audio/wav", data: Base64.strict_encode64(File.binread(wav)) } },
            ] }],
            generationConfig: { responseMimeType: "application/json", thinkingConfig: { thinkingBudget: 0 } },
          }
          res = Net::HTTP.post(uri, body.to_json, "Content-Type" => "application/json")
          text = JSON.parse(res.body).dig("candidates", 0, "content", "parts", 0, "text")
          JSON.parse(text.to_s)["heard"].to_s.strip
        rescue StandardError
          nil
        end

        def gemini_key
          return ENV["GEMINI_API_KEY"] unless ENV["GEMINI_API_KEY"].to_s.empty?

          path = File.expand_path("~/.config/master/env")
          return unless File.file?(path)

          File.foreach(path) do |line|
            key, value = line.strip.sub(/\Aexport\s+/, "").split("=", 2)
            return value.to_s.delete(%("')) if key == "GEMINI_API_KEY"
          end
          nil
        end

        def read_matches(stdout, heard, on_partial)
          stdout.each_line do |line|
            text = line.strip
            next if text.empty?

            heard << text
            on_partial&.call(text)
          end
        rescue IOError
          nil
        end

        # Stopping early keeps what was heard so far; the recogniser's own
        # end of speech is the other way out, and it needs nothing from here.
        def halt(wait_thr)
          return unless wait_thr.alive?

          Process.kill("TERM", wait_thr.pid)
          wait_thr.join(1)
        rescue Errno::ESRCH
          nil
        end
      end
    end
  end
end
