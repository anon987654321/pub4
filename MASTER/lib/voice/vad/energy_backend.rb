# frozen_string_literal: true

module Master
  module Voice
    class Vad
      # Pure RMS → [0,1] score. Always available; no native dependencies.
      class EnergyBackend
        def initialize(config = {})
          @floor = (config[:energy_floor] || Vad::DEFAULTS[:energy_floor]).to_f
          @ceiling = (config[:energy_ceiling] || Vad::DEFAULTS[:energy_ceiling]).to_f
          @ceiling = @floor + 0.01 if @ceiling <= @floor
        end

        def name = :energy

        def reset!
          # Stateless.
        end

        # floats: Array of Float in [-1, 1]
        # rms: optional precomputed RMS
        def score(floats, rms: nil)
          level = rms || rms_of(floats)
          return 0.0 if level <= @floor
          return 1.0 if level >= @ceiling

          ((level - @floor) / (@ceiling - @floor)).clamp(0.0, 1.0)
        end

        private

        def rms_of(floats)
          return 0.0 if floats.empty?

          Math.sqrt(floats.sum { |x| x * x } / floats.length)
        end
      end
    end
  end
end
