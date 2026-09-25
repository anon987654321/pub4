# frozen_string_literal: true

module Master
  module Music
    # Grid + humanized time. `dilla: true` nudges odd sixteenths late.
    module Rhythm
      module_function

      def grid(bars: 1, beats_per_bar: 4, subdivisions_per_beat: 4, bpm: 140.0,
               swing: 0.0, dilla: false, seed: 42)
        beat_seconds = 60.0 / bpm
        step_seconds = beat_seconds / subdivisions_per_beat
        count = bars * beats_per_bar * subdivisions_per_beat
        rng = Random.new(seed)

        Array.new(count) do |step|
          at = step * step_seconds
          dilla_offset = dilla && step.odd? ? step_seconds * (0.12 + rng.rand * 0.10) : 0.0
          swing_offset = swing.positive? && step.odd? ? step_seconds * swing : 0.0
          at += dilla_offset + swing_offset
          { step:, at:, offset: dilla_offset + swing_offset }
        end
      end
    end
  end
end
