# frozen_string_literal: true

require_relative "audio_sink"
require_relative "synth"

module Master
  module Music
    # Live playback: generate and push frames through an AudioSink as they
    # are made, instead of Synth.render's write-a-WAV-then-play. Reuses
    # Synth.oscillator for the sample math rather than a second copy of the
    # four waveform formulas.
    module Realtime
      RATE = AudioSink::SAMPLE_RATE
      BLOCK_FRAMES = 1_024

      module_function

      # One shape, held for the duration.
      def play(shape: :sine, hz: 440.0, seconds: 3.0, sink: AudioSink.new)
        shape = shape.to_sym
        total_frames = (seconds * RATE).round
        sink.open do |s|
          each_block(total_frames) do |first_frame, count|
            s.write(Array.new(count) { |i| Synth.oscillator(shape, hz, (first_frame + i).to_f / RATE) })
          end
        end
      end

      # sine -> square -> triangle, crossfading at each boundary so the
      # transition is a blend rather than a splice. crossfade_seconds is
      # clamped to at most a third of one segment so three transitions never
      # overlap on a short total duration.
      def morph(hz: 440.0, seconds: 6.0, shapes: %i[sine square triangle], crossfade_seconds: 0.3, sink: AudioSink.new)
        segment_seconds = seconds / shapes.length
        fade = [crossfade_seconds, segment_seconds / 3.0].min
        total_frames = (seconds * RATE).round

        sink.open do |s|
          each_block(total_frames) do |first_frame, count|
            s.write(Array.new(count) { |i| morph_sample(shapes, hz, (first_frame + i).to_f / RATE, segment_seconds, fade) })
          end
        end
      end

      def morph_sample(shapes, hz, t, segment_seconds, fade)
        index = (t / segment_seconds).to_i.clamp(0, shapes.length - 1)
        into_segment = t - (index * segment_seconds)
        current = Synth.oscillator(shapes[index], hz, t)

        next_shape = shapes[index + 1]
        return current unless next_shape && into_segment >= segment_seconds - fade

        # Linear crossfade: weight sweeps 0 -> 1 across the last `fade`
        # seconds of the segment, so it always sums to 1 and the blended
        # sample cannot exceed either pure waveform's own [-1, 1] range.
        weight = (into_segment - (segment_seconds - fade)) / fade
        nxt = Synth.oscillator(next_shape, hz, t)
        ((1 - weight) * current) + (weight * nxt)
      end

      def each_block(total_frames)
        frame = 0
        while frame < total_frames
          count = [BLOCK_FRAMES, total_frames - frame].min
          yield frame, count
          frame += count
        end
      end
      private_class_method :each_block
    end
  end
end
