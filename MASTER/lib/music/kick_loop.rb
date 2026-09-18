# frozen_string_literal: true

require_relative "waveform"

module Master
  module Music
    # One seamless bar of hard techno kick, generated without external tools.
    class KickLoop
      RATE = 44_100
      BPM = 140.0
      BEATS = 4
      KICK_SECONDS = 0.32

      class << self
        def render(destination: nil)
          destination ||= default_destination

          bar_seconds = 60.0 / BPM * BEATS
          frames = (bar_seconds * RATE).round
          beat_frames = (bar_seconds / BEATS * RATE).round
          samples = Array.new(frames, 0.0)

          BEATS.times { |beat| render_kick!(samples, beat * beat_frames) }
          Waveform.write_wav(destination, samples, rate: RATE)
        end

        private

        def default_destination
          File.expand_path("~/master-techno-kick-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.wav")
        end

        def render_kick!(samples, start)
          phase = 0.0
          attack_frames = (RATE * 0.0012).round
          kick_frames = (KICK_SECONDS * RATE).round

          kick_frames.times do |offset|
            frame = start + offset
            break if frame >= samples.length

            t = offset.to_f / RATE
            attack = [offset.to_f / attack_frames, 1.0].min
            hz = 42.0 + 58.0 * Math.exp(-t * 11.0)
            phase += 2 * Math::PI * hz / RATE
            body = Math.sin(phase) * Math.exp(-t * 9.0)
            click = Math.sin(2 * Math::PI * 1800 * t) * Math.exp(-t * 120)
            sample = body + (click * attack)
            samples[frame] += (Math.tanh(sample * 3.0) / Math.tanh(3.0)) * 0.95 * attack
          end
        end
      end
    end
  end
end
