# frozen_string_literal: true

require "open3"
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
        # The gate sits above the room, not at a fixed level: a fixed 1%
        # never opened in a quiet room, and a fixed 0.05% opened on a
        # laptop's own noise, which peaks near 0.4%, so every take was a
        # sixth of a second of hiss. Half a second of the room is measured,
        # and speech must rise to three times its level to start a take.
        ROOM_S = 0.5
        ROOM_TTL_S = 60
        GATE_OVER_ROOM = 3.0
        GATE_FLOOR = 0.3
        # High enough that a loud room still puts the gate above its noise:
        # under the room, every take would be twelve seconds of it.
        GATE_CEILING = 60.0
        MAX_TAKE_S = 12
        # Under this the take is a click or a breath, not a phrase.
        MIN_TAKE_S = 0.4

        # The start gate, in percent of full scale, for a room at room_percent.
        def self.gate_for(room_percent) = (room_percent * GATE_OVER_ROOM).clamp(GATE_FLOOR, GATE_CEILING)

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

        # termux-speech-to-text prints the phrase and exits. Device has no
        # speech helper; the command is the recogniser.
        def termux_listen(stop:, on_partial:)
          stdin = stdout = nil
          stdin, stdout, wait_thr = Open3.popen2("termux-speech-to-text")
          stdin.close
          heard = []
          reader = Thread.new { read_matches(stdout, heard, on_partial) }
          # Enter asks the recogniser to finish. Killing it here drops the
          # phrase before it is printed, so wait for the line, then stop.
          sleep 0.05 while wait_thr.alive? && heard.empty? && !stop.call
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 4
          sleep 0.05 while wait_thr.alive? && heard.empty? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
          halt(wait_thr) if wait_thr.alive?
          reader.join(1)
          heard.last
        ensure
          stdout&.close unless stdout&.closed?
          stdin&.close unless stdin&.closed?
        end

        # sox ends the take on silence. The words are the transcription of
        # that file, not a guess, and the reply itself still goes through the
        # session so the next turn can hear this one.
        def host_listen(stop:, on_partial:)
          wav = File.join(Dir.tmpdir, "master-face-#{Process.pid}.wav")
          File.delete(wav) if File.exist?(wav)
          pid = Process.spawn(*SOX, wav, *silence_effect, out: File::NULL, err: File::NULL)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          sleep 0.05 while alive?(pid) && !stop.call && (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) < MAX_TAKE_S
          finish_sox(pid)
          return unless File.size?(wav).to_i > (MIN_TAKE_S * 16_000 * 2)

          text = transcribe(wav)
          on_partial&.call(text) if text && !text.empty?
          text
        ensure
          File.delete(wav) if wav && File.exist?(wav)
        end

        # sox's silence effect: a take starts when the level holds over the
        # gate for 50 ms, and ends after 0.8 s under half the gate.
        def silence_effect
          gate = gate_percent
          ["silence", "1", "0.05", "#{gate.round(3)}%", "1", "0.8", "#{(gate / 2).round(3)}%"]
        end

        # The room is measured again after a minute, so a fan that starts or
        # stops moves the gate with it.
        def gate_percent
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          if @room.nil? || now - @room_at > ROOM_TTL_S
            @room = room_peak_percent
            @room_at = now
          end
          self.class.gate_for(@room)
        end

        # The room's level as a percent: the 99th-percentile sample, so one
        # knock does not raise the gate, taken after the first 150 ms, where
        # opening the device clicks at up to 5%.
        def room_peak_percent
          raw, = Open3.capture2("sox", "-q", "-d", "-r", "16000", "-c", "1", "-b", "16", "-e", "signed",
                                "-t", "raw", "-", "trim", "0", (ROOM_S + 0.15).to_s, binmode: true, err: File::NULL)
          samples = raw.unpack("s<*").drop(2_400).map(&:abs).sort
          samples.empty? ? 0.0 : samples[(samples.size * 0.99).floor] * 100.0 / 32_768
        rescue StandardError
          0.0
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
