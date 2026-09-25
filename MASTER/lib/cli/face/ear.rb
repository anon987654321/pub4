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
        RATE_HZ = 16_000
        FRAME_BYTES = 640 # 20 ms
        START_FRAMES = 3 # 60 ms over the gate starts a take
        END_FRAMES = 40 # 0.8 s under half of it ends one
        PREROLL_FRAMES = 12
        PARTIAL_EVERY_S = 1.0
        # Under this the take is a click or a breath, not a phrase.
        MIN_TAKE_S = 0.4

        # The start gate, in percent of full scale, for a room at room_percent.
        def self.gate_for(room_percent) = (room_percent * GATE_OVER_ROOM).clamp(GATE_FLOOR, GATE_CEILING)

        def initialize(device: Master::Device, capture: nil, transcriber: nil)
          @device = device
          @capture = capture || -> { open_stream }
          @transcriber = transcriber || ->(pcm) { transcribe(pcm) }
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
        # The host ear streams: sox hands raw 16 kHz samples to Ruby, which
        # finds the start and end of speech itself, so the words can be
        # transcribed while the take is still going. Once a second the take so
        # far goes to Gemini and its words are shown, the way the web face
        # shows the browser's interim results; the pause that ends the take
        # sends the whole of it once more, and that transcript is the one kept.
        def host_listen(stop:, on_partial:)
          stream = @capture.call
          take = capture_take(stream, stop:, on_partial:)
          return unless take && take.bytesize > (MIN_TAKE_S * RATE_HZ * 2)

          @finished = true
          text = @transcriber.call(take)
          on_partial&.call(text) if text && !text.empty?
          text
        ensure
          close_stream(stream)
        end

        # Reads 20 ms frames until speech has started and then paused, or the
        # caller stops. A quarter second before the start is kept, so the
        # first syllable is not clipped by the gate that found it.
        def capture_take(stream, stop:, on_partial:)
          gate = gate_percent * 327.68
          @finished = false
          preroll = []
          take = nil
          loud = quiet = 0
          last_partial = 0
          until stop.call
            frame = stream.read(FRAME_BYTES)
            break if frame.nil? || frame.empty?

            peak = frame.unpack("s<*").map(&:abs).max.to_i
            if take.nil?
              preroll << frame
              preroll.shift while preroll.size > PREROLL_FRAMES
              loud = peak > gate ? loud + 1 : 0
              take = preroll.join if loud >= START_FRAMES
              next
            end

            take << frame
            quiet = peak < gate / 2 ? quiet + 1 : 0
            break if quiet >= END_FRAMES || take.bytesize >= MAX_TAKE_S * RATE_HZ * 2

            # A second more of speech since the last interim, counted in the
            # audio rather than on the clock, and none still in flight.
            next unless take.bytesize - last_partial >= PARTIAL_EVERY_S * RATE_HZ * 2 && !@worker&.alive?

            last_partial = take.bytesize
            @worker = partial(take.dup, on_partial)
          end
          take
        end

        # One interim transcript, off the reading thread. Once the final one is
        # under way a late interim is dropped, so the words never step back.
        def partial(pcm, on_partial)
          return unless on_partial

          Thread.new do
            text = @transcriber.call(pcm)
            on_partial.call(text) if text && !text.empty? && !@finished
          end
        end

        def open_stream
          IO.popen(%w[sox -q -d -r 16000 -c 1 -b 16 -e signed -t raw -], "rb", err: File::NULL)
        end

        def close_stream(stream)
          return unless stream

          Process.kill("INT", stream.pid) if stream.respond_to?(:pid) && stream.pid
          stream.close
        rescue Errno::ESRCH, IOError
          nil
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

        def transcribe(pcm)
          key = gemini_key
          return unless key

          require "net/http"
          require "json"
          require "base64"
          uri = URI("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=#{key}")
          body = {
            contents: [{ parts: [
              { text: 'Transcribe the speech. Reply as JSON: {"heard":"..."} . Empty heard when there is no speech.' },
              { inline_data: { mime_type: "audio/wav", data: Base64.strict_encode64(wav_bytes(pcm)) } },
            ] }],
            generationConfig: { responseMimeType: "application/json", thinkingConfig: { thinkingBudget: 0 } },
          }
          res = Net::HTTP.post(uri, body.to_json, "Content-Type" => "application/json")
          text = JSON.parse(res.body).dig("candidates", 0, "content", "parts", 0, "text")
          JSON.parse(text.to_s)["heard"].to_s.strip
        rescue StandardError
          nil
        end

        # A 16 kHz mono 16-bit wav around raw samples.
        def wav_bytes(pcm)
          ["RIFF", 36 + pcm.bytesize, "WAVE", "fmt ", 16, 1, 1, RATE_HZ, RATE_HZ * 2, 2, 16, "data", pcm.bytesize]
            .pack("a4Va4a4VvvVVvva4V") + pcm
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
