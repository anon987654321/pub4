# frozen_string_literal: true

module Master
  module CLI
    module Face
      # The face's voice: MASTER's own TTS, played on whatever the host has,
      # with the mouth driven by the loudness of the audio being played.
      #
      # Synthesis is Voice::Playback.synthesize, which is Speech with the
      # policy's rate and pitch; Speech picks the voice from data/voice.yml's
      # rotation and applies its post_chain, so the phone hears the speaker
      # the terminal and the web face hear. The envelope is the decoded audio's
      # loudness in twentieths of a second, read before playback starts; with
      # no ffmpeg the mouth moves on a timer instead.
      class Mouth
        FRAME_S = 0.05
        RATE = 8_000
        # Without an envelope a termux-media-player take has no known length,
        # and speech runs near fourteen characters a second.
        CHARS_PER_S = 14.0

        def initialize(device: Master::Device, synthesize: ->(text) { Master::Voice::Playback.synthesize(text) })
          @device = device
          @synthesize = synthesize
        end

        # Nil when the mouth can speak. Playback.enabled? is the switch the
        # session obeys — MASTER_CLI_SPEAK=0, MASTER_SKIP_TTS, CI, no terminal
        # — so the face falls silent exactly where the session does.
        def missing
          return "voice0: off here — replies stay text" unless Master::Voice::Playback.enabled?
          return if termux? || Master::Voice::Playback.player

          "voice0: no player — on Termux #{Ear::HINT}; replies stay text"
        end

        def available? = missing.nil?

        # Speaks text a sentence at a time, calling on_chunk with each before
        # it is heard and on_level with the mouth's opening while it plays.
        # stop ends it between frames. False when nothing could be spoken.
        def say(text, on_level:, on_chunk: nil, stop: -> { false })
          return false unless available?

          spoken = false
          chunks(text).each do |part|
            break if stop.call

            path = @synthesize.call(part)
            next unless path

            on_chunk&.call(part)
            play(path, part, on_level:, stop:)
            spoken = true
          ensure
            File.delete(path) if path && File.exist?(path)
          end
          spoken
        end

        # Loudness per frame, scaled so the loudest frame opens the mouth
        # fully. Empty when the audio cannot be decoded.
        def envelope(path)
          out, _err, status = Master::Io::Exec.capture3(
            "ffmpeg", "-v", "quiet", "-i", path, "-ac", "1", "-ar", RATE.to_s, "-f", "s16le", "-", timeout: 20
          )
          return [] unless status.success?

          levels(out.b.unpack("s<*"))
        rescue SystemCallError
          []
        end

        private

        def termux?
          @device.android? && Master::Voice::Playback.which("termux-media-player")
        end

        def chunks(text)
          parts = Master::Voice::Speech.chunks(text)
          parts.empty? ? [text.to_s.strip].reject { |part| part.empty? } : parts
        end

        def levels(samples)
          per = (RATE * FRAME_S).to_i
          rms = samples.each_slice(per).map { |slice| Math.sqrt(slice.sum { |s| s * s } / slice.size.to_f) }
          peak = rms.max.to_f
          peak.positive? ? rms.map { |value| value / peak } : []
        end

        def play(path, part, on_level:, stop:)
          levels = envelope(path)
          length = levels.empty? ? part.length / CHARS_PER_S : levels.size * FRAME_S
          playing, halt = start(path)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          loop do
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
            break quietly(halt) if stop.call
            break unless playing.call(elapsed, length)

            on_level.call(levels.empty? ? nil : levels.fetch((elapsed / FRAME_S).floor, 0.0))
            sleep FRAME_S
          end
          on_level.call(0.0)
        end

        # Two callables: whether the take is still playing, and how to cut it
        # short. A blocking player is a child to wait on; termux-media-player
        # returns at once, so its take lasts as long as the audio does.
        def start(path)
          return termux_take(path) if termux?

          name, args = Master::Voice::Playback.player
          pid = Process.spawn(name, *args, path, out: File::NULL, err: File::NULL)
          waiter = Process.detach(pid)
          [->(_elapsed, _length) { waiter.alive? }, -> { Process.kill("TERM", pid) }]
        end

        def termux_take(path)
          pid = Process.spawn("termux-media-player", "play", path, out: File::NULL, err: File::NULL)
          Process.detach(pid)
          [->(elapsed, length) { elapsed < length }, -> { system("termux-media-player", "stop", out: File::NULL, err: File::NULL) }]
        end

        def quietly(halt)
          halt.call
        rescue Errno::ESRCH, Master::Device::Error
          nil
        end
      end
    end
  end
end
