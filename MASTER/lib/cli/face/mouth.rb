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
        RATE = 4_000
        # Without an envelope a termux-media-player take has no known length,
        # and speech runs near fourteen characters a second.
        CHARS_PER_S = 14.0

        def initialize(device: Master::Device, synthesize: ->(text) { Master::Voice::Playback.synthesize(text) })
          @device = device
          @synthesize = synthesize
          @last_error = nil
        end

        attr_reader :last_error

        # Nil when the mouth can speak. Playback.enabled? is the switch the
        # session obeys — MASTER_CLI_SPEAK=0, MASTER_SKIP_TTS, CI, no terminal.
        # A face also needs a synthesiser, because player presence alone says
        # nothing about whether Speech can produce audio.
        def missing
          return "voice0: off here — replies stay text" unless Master::Voice::Playback.enabled?
          return "voice0: speech synthesis unavailable — replies stay text" unless Master::Voice::Speech.available?
          return if Master::Device::Audio.available? || Master::Voice::Playback.player || direct_speech?

          "voice0: no audio path — #{Ear::HINT}; replies stay text"
        end

        def available? = missing.nil?

        # Speaks text a sentence at a time, calling on_chunk with each before
        # it is heard and on_level with the mouth's opening while it plays.
        # stop ends it between frames. False when nothing could be spoken.
        def say(text, on_level:, on_chunk: nil, stop: -> { false })
          @last_error = nil
          unless available?
            @last_error = missing
            Master::Trace::Dmesg.status("voice0", @last_error)
            return false
          end

          spoken = false
          chunks(text).each do |part|
            break if stop.call

            path = @synthesize.call(part)
            if path && File.exist?(path)
              on_chunk&.call(part)
              played = play(path, part, on_level:, stop:)
              played = Master::Device::Audio.speak(part) if !played && @device.android?
              played = direct_speak(part) unless played
              spoken ||= played
              unless played
                @last_error = "audio playback failed"
                show_direct_fallback
              end
            else
              spoken ||= Master::Device::Audio.speak(part) if @device.android?
              spoken ||= direct_speak(part)
              unless spoken
                @last_error = "speech synthesis failed"
                show_direct_fallback
              end
            end
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
          @device.android? && Master::Device::Audio.media_player_available?
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
          envelope_job = Thread.new { envelope(path) }
          state = start(path)
          playing, halt, status = state
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          stopped = false
          levels = []
          length = part.length / CHARS_PER_S
          loop do
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
            if envelope_job && envelope_job.join(0)
              levels = envelope_job.value
              length = levels.size * FRAME_S unless levels.empty?
              envelope_job = nil
            end
            if stop.call
              stopped = true
              quietly(halt)
              break
            end
            break unless playing.call(elapsed, length)

            on_level.call(levels.empty? ? nil : levels.fetch((elapsed / FRAME_S).floor, 0.0))
            sleep FRAME_S
          end
          if stopped
            envelope_job&.kill
            on_level.call(0.0)
            return true
          end

          levels = envelope_job.value if envelope_job
          on_level.call(0.0)

          process_status = status.call
          return true if process_status == true

          process_status ? process_status.success? : false
        rescue StandardError => e
          Master::Trace::Dmesg.status("voice0", "playback failed, #{e.class}: #{e.message}")
          false
        end

        # Two callables: whether the take is still playing, and how to cut it
        # short. A blocking player is a child to wait on; termux-media-player
        # returns at once, so its take lasts as long as the audio does.
        def start(path)
          return termux_take(path) if termux?

          name, args = Master::Voice::Playback.player
          pid = Process.spawn(name, *args, path, out: File::NULL, err: File::NULL)
          waiter = Process.detach(pid)
          [->(_elapsed, _length) { waiter.alive? }, -> { Process.kill("TERM", pid) }, -> { waiter.value }]
        end

        def termux_take(path)
          Master::Device::Audio.play(path)
          [->(elapsed, length) { elapsed < length }, -> { Master::Device::Audio.stop }, -> { true }]
        end

        def direct_speech?
          !RUBY_PLATFORM.include?("openbsd") && Master::Voice::Playback.which("say")
        end

        def direct_speak(text)
          return false unless direct_speech?

          ok = system("say", text.to_s, out: File::NULL, err: File::NULL)
          Master::Trace::Dmesg.status("voice0", "direct speech #{ok ? "ready" : "failed"}")
          @last_error = "direct speech failed" unless ok
          ok
        rescue StandardError => e
          Master::Trace::Dmesg.status("voice0", "direct speech failed, #{e.class}: #{e.message}")
          false
        end

        def show_direct_fallback
          return unless direct_speech?

          Master::Trace::Dmesg.status("voice0", "synthesis unavailable, using direct speech")
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
