# frozen_string_literal: true

require "open3"

module Master
  module CLI
    module Face
      # The face's microphone. It streams raw samples from sox, or from parec
      # on a phone, finds the start and end of speech itself, and hands the
      # take to a Transcriber: whisper.cpp where it is installed, Gemini where
      # it is not. A phone without whisper uses Termux:API's
      # termux-speech-to-text instead. The words then go through the session,
      # which is what the next turn remembers.
      #
      # Without a recogniser the ear says what is missing and hears nothing. A
      # typed line is the fallback; a guessed transcription never is.
      class Ear
        HINT = "install the Termux:API app, then pkg install termux-api"
        # Termux has no sox audio driver. PulseAudio's OpenSL ES source reads
        # the phone's microphone, and parec streams it as raw samples.
        PULSE = %w[pulseaudio --start --load=module-sles-source --exit-idle-time=-1].freeze
        PAREC = %w[parec --raw --format=s16le --rate=16000 --channels=1 --latency-msec=20].freeze
        SOX = %w[sox -q -d -r 16000 -c 1 -b 16 -e signed -t raw -].freeze
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

        # transcriber takes the whole take and interim the take so far; both
        # default to words, which picks whisper or Gemini.
        def initialize(device: Master::Device, capture: nil, transcriber: nil, interim: nil, words: Transcriber.new)
          @device = device
          @words = words
          @capture = capture || -> { open_stream }
          @transcriber = transcriber || words.method(:final)
          @interim = interim || transcriber || words.method(:interim)
        end

        # Nil when the ear can listen, otherwise the sentence that says why not.
        def missing
          return (streaming? ? nil : termux_missing) if @device.android?
          return "mic0: sox missing — type instead" unless on_path?("sox")
          return "mic0: #{@words.describe} — type instead" unless @words.lane

          nil
        end

        def available? = missing.nil?

        # Listens until stop answers true or the recogniser ends on silence,
        # handing each partial match to on_partial as it arrives. Returns the
        # last match, which is the fullest, or nil when nothing was heard.
        def listen(stop:, on_partial: nil)
          return termux_listen(stop:, on_partial:) if @device.android? && !streaming?

          heard = host_listen(stop:, on_partial:)
          return heard unless @mute && @device.android?

          termux_listen(stop:, on_partial:)
        end

        private

        def termux_missing
          return nil if Master::Voice::Playback.which("termux-speech-to-text")

          "mic0: termux-speech-to-text missing — #{HINT}; type instead"
        end

        def on_path?(cmd) = Master::Voice::Playback.which(cmd)

        # A phone streams through whisper once the Termux setup has put
        # whisper-cli, a model and parec in place, and until parec once gives
        # no sound at all, which is a microphone Termux failed to open.
        def streaming?
          !@mute && @words.lane == :whisper && on_path?("parec")
        end

        def record_argv = @device.android? ? PAREC : SOX

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

        # The ear streams: sox or parec hands raw 16 kHz samples to Ruby, which
        # finds the start and end of speech itself, so the words can be
        # transcribed while the take is still going. Once a second the take so
        # far goes to the fast model and its words are shown, the way the web
        # face shows the browser's interim results; the pause that ends the
        # take sends the whole of it to the accurate one, and that transcript
        # is the one kept.
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
        # caller stops.
        def capture_take(stream, stop:, on_partial:)
          gate = gate_percent * 327.68
          @finished = false
          take = await_speech(stream, gate, stop)
          quiet = last_partial = 0
          until take.nil? || stop.call
            frame = stream.read(FRAME_BYTES)
            break if frame.nil? || frame.empty?

            take << frame
            quiet = peak(frame) < gate / 2 ? quiet + 1 : 0
            break if quiet >= END_FRAMES || take.bytesize >= MAX_TAKE_S * RATE_HZ * 2

            # A second more of speech since the last interim, counted in the
            # audio rather than on the clock, and none still in flight.
            next unless take.bytesize - last_partial >= PARTIAL_EVERY_S * RATE_HZ * 2 && !@worker&.alive?

            last_partial = take.bytesize
            @worker = partial(take.dup, on_partial)
          end
          take
        end

        # The start of a take, or nil when the caller stops or the stream
        # ends first. A quarter second before the start is kept, so the first
        # syllable is not clipped by the gate that found it. A stream with no
        # first frame at all marks the ear mute.
        def await_speech(stream, gate, stop)
          preroll = []
          loud = 0
          until stop.call
            frame = stream.read(FRAME_BYTES)
            @mute = true if preroll.empty? && (frame.nil? || frame.empty?)
            return if frame.nil? || frame.empty?

            preroll << frame
            preroll.shift while preroll.size > PREROLL_FRAMES
            loud = peak(frame) > gate ? loud + 1 : 0
            return preroll.join if loud >= START_FRAMES
          end
        end

        def peak(frame) = frame.unpack("s<*").map(&:abs).max.to_i

        # One interim transcript, off the reading thread. Once the final one is
        # under way a late interim is dropped, so the words never step back.
        def partial(pcm, on_partial)
          return unless on_partial

          Thread.new do
            text = @interim.call(pcm)
            on_partial.call(text) if text && !text.empty? && !@finished
          end
        end

        def open_stream
          system(*PULSE, out: File::NULL, err: File::NULL) if @device.android?
          IO.popen(record_argv, "rb", err: File::NULL)
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
          stream = open_stream
          raw = stream.read(((ROOM_S + 0.15) * RATE_HZ * 2).to_i).to_s
          samples = raw.unpack("s<*").drop(2_400).map(&:abs).sort
          samples.empty? ? 0.0 : samples[(samples.size * 0.99).floor] * 100.0 / 32_768
        rescue StandardError
          0.0
        ensure
          close_stream(stream)
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
