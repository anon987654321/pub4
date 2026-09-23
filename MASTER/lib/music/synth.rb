# frozen_string_literal: true

require_relative "waveform"

module Master
  module Music
    # Minimal native synth: one waveform, one pitch, one duration, one file.
    class Synth
      RATE = 44_100
      SHAPES = %i[sine square triangle saw white brown].freeze

      class << self
        def render(shape: :sine, hz: 440.0, seconds: 1.0, destination: nil, seed: 42)
          shape = shape.to_sym
          validate_shape!(shape)
          destination ||= default_destination(shape)
          frames = (seconds * RATE).round
          samples = build_samples(shape, hz, frames, seed)
          Waveform.write_wav(destination, samples, rate: RATE)
        end

        def play(path, loop: false)
          raise ArgumentError, "missing audio #{path}" unless File.file?(path)

          cmd = if loop && tool_available?("ffplay")
                  ["ffplay", "-loop", "0", "-nodisp", "-autoexit", "-loglevel", "quiet", "-i", path]
                elsif File.exist?("/usr/bin/afplay")
                  ["afplay", path]
                elsif tool_available?("ffplay")
                  ["ffplay", "-nodisp", "-autoexit", "-i", path]
                else
                  raise "afplay or ffplay required"
                end

          log = File.open("/tmp/master-synth-play.log", "a")
          pid = Process.spawn(*cmd, out: log, err: log)
          log.close
          Process.detach(pid)
          pid
        end

        # Public: Realtime.morph generates frame-by-frame rather than as one
        # buffer, so it calls this directly instead of duplicating the four
        # waveform formulas.
        def oscillator(shape, hz, t)
          phase = (hz * t) % 1.0
          case shape
          when :square then phase < 0.5 ? 1.0 : -1.0
          when :triangle then phase < 0.5 ? 4.0 * phase - 1.0 : 3.0 - 4.0 * phase
          when :saw then 2.0 * phase - 1.0
          else Math.sin(2 * Math::PI * phase)
          end
        end

        private

        def validate_shape!(shape)
          return if SHAPES.include?(shape)

          raise ArgumentError, "unknown shape #{shape}; valid: #{SHAPES.join(', ')}"
        end

        def tool_available?(name)
          system("command", "-v", name, out: File::NULL, err: File::NULL)
        end

        def default_destination(shape)
          File.expand_path("~/master-#{shape}-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.wav")
        end

        def build_samples(shape, hz, frames, seed)
          return noise(shape, frames, seed) if %i[white brown].include?(shape)

          Array.new(frames) { |i| oscillator(shape, hz, i.to_f / RATE) }
        end

        def noise(shape, frames, seed)
          rng = Random.new(seed)
          value = 0.0
          Array.new(frames) do
            raw = rng.rand * 2.0 - 1.0
            value = if shape == :white
                      raw
                    else
                      (value + 0.02 * raw).clamp(-1.0, 1.0)
                    end
            value * 0.8
          end
        end
      end
    end
  end
end
