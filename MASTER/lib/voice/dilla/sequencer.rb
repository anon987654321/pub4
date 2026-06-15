# frozen_string_literal: true

module Master
  module Voice
    module Dilla
      # CZ01/CZ02: 16-step beat sequencer with swing quantisation.
      class Sequencer
        STEPS = 16
        DEFAULT_BPM = 92
        DEFAULT_SWING = 58

        def initialize(bpm: DEFAULT_BPM, swing_percent: DEFAULT_SWING, mood: :neutral)
          @bpm = bpm
          @swing = swing_percent.clamp(0, 100)
          @mood = mood
          @grid = Array.new(STEPS) { |_| { kick: false, snare: false, hat: false } }
        end

        def set_step(index, instrument:, on: true)
          @grid[index % STEPS][instrument] = on
          self
        end

        def swing_offset(step)
          step.odd? ? (@swing / 100.0) * 0.04 : 0.0
        end

        def step_duration_sec
          60.0 / (@bpm * 4)
        end

        def to_h
          { bpm: @bpm, swing: @swing, mood: @mood, steps: @grid, step_duration: step_duration_sec }
        end

        def export_wav_metadata
          { loop: true, acid: true, bpm: @bpm, steps: STEPS }
        end
      end
    end
  end
end