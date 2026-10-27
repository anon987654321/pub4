# frozen_string_literal: true

module Master
  module Voice
    module BootSound
      # The startup sound's signal chain after the voices: the pad's lowpass sweep, the room, the tape, the
      # master fades and the fixed-gain normalisation, plus the bit crush and sample-and-hold of the bells.
      # Every stage takes channels of floats and returns new ones, so the render reads as a pipeline.
      module Dsp
        RATE = 22_050
        TAU = Math::PI * 2

        module_function

        def raised_cosine(phase)
          return 0.0 unless phase.positive?
          return 1.0 if phase >= 1

          0.5 - (0.5 * Math.cos(Math::PI * phase))
        end

        # A one-pole lowpass whose cutoff opens exponentially from from_hz to to_hz over sweep_ms, then
        # settles linearly to settle_hz over settle_ms.
        def lowpass_sweep(samples, filter)
          state = 0.0
          samples.each_with_index.map do |sample, i|
            coefficient = 1 - Math.exp(-TAU * cutoff(filter, i.to_f / RATE) / RATE)
            state += coefficient * (sample - state)
          end
        end

        def cutoff(filter, seconds)
          from = filter.fetch("from_hz").to_f
          to = filter.fetch("to_hz").to_f
          sweep = filter.fetch("sweep_ms") / 1000.0
          return from * ((to / from)**(seconds / sweep)) if seconds < sweep

          settled = [(seconds - sweep) * 1000.0 / filter.fetch("settle_ms"), 1.0].min
          to - ((to - filter.fetch("settle_hz")) * settled)
        end

        # A Schroeder room: damped combs in parallel, then allpasses in series. Left and right use different
        # delay lengths, which is where the width comes from.
        def room(stereo, room)
          stereo.zip(%w[left right]).map do |channel, side|
            wet = allpasses(combs(channel, room, delays: room.fetch("combs_#{side}")), room.fetch("allpasses_#{side}"))
            channel.each_with_index.map { |dry, i| (dry * room.fetch("dry")) + (wet[i] * room.fetch("wet")) }
          end
        end

        def combs(channel, room, delays:)
          out = Array.new(channel.size, 0.0)
          delays.each { |delay| comb_into(out, channel, room:, delay:) }
          out.map { |sample| sample / delays.size }
        end

        def comb_into(out, channel, room:, delay:)
          buffer = Array.new(delay, 0.0)
          damping = room.fetch("damping")
          damped = 0.0

          channel.each_with_index do |sample, i|
            delayed = buffer[i % delay]
            damped = (delayed * (1 - damping)) + (damped * damping)
            buffer[i % delay] = sample + (room.fetch("feedback") * damped)
            out[i] += delayed
          end
        end

        def allpasses(channel, delays)
          delays.reduce(channel) do |signal, delay|
            buffer = Array.new(delay, 0.0)

            signal.each_with_index.map do |sample, i|
              out = (-0.5 * sample) + buffer[i % delay]
              buffer[i % delay] = sample + (0.5 * out)
              out
            end
          end
        end

        # Soft saturation and a lowpassed hiss that fades in with the pad. The noise is seeded, so the render
        # stays deterministic.
        def tape(stereo, tape, swell:)
          hiss = hiss_source(tape)
          drive = tape.fetch("drive")

          stereo.map do |channel|
            channel.each_with_index.map do |sample, i|
              (Math.tanh(drive * sample) / drive) + (hiss.call * raised_cosine(i.to_f / RATE / swell))
            end
          end
        end

        # One smoothed noise stream that runs on through both channels, as the hiss always has.
        def hiss_source(tape)
          random = ::Random.new(tape.fetch("seed"))
          smoothing = tape.fetch("hiss_smoothing")
          level = 10**(tape.fetch("hiss_dbfs") / 20.0)
          noise = 0.0
          -> { (noise += smoothing * (((random.rand * 2) - 1) - noise)) * level }
        end

        # A raised-cosine fade over everything at both ends, so not even the room or the hiss starts hard.
        def master(stereo, master)
          frames = stereo.first.size
          fade_in = master.fetch("fade_in_ms") * RATE / 1000.0
          tail = master.fetch("tail_ms") * RATE / 1000.0

          stereo.map do |channel|
            channel.each_with_index.map do |sample, i|
              sample * raised_cosine(i / fade_in) * raised_cosine((frames - i) / tail)
            end
          end
        end

        # One fixed gain from the measured peak: deterministic, for the reason voice.yml gives for refusing
        # loudnorm.
        def normalise(stereo, ceiling_dbfs)
          peak = stereo.flatten.map(&:abs).max
          return stereo unless peak.positive?

          gain = (10**(ceiling_dbfs / 20.0)) / peak
          stereo.map { |channel| channel.map { |sample| (sample * gain).clamp(-1.0, 1.0) } }
        end

        def crush(sample, bits)
          levels = (2**(bits - 1)).to_f
          (sample * levels).round / levels
        end

        # Sample-and-hold: every `every` samples the value is taken and kept, a lower rate on the same clock.
        def hold(samples, every)
          held = 0.0
          samples.each_with_index.map { |sample, i| (i % every).zero? ? (held = sample) : held }
        end
      end
    end
  end
end
