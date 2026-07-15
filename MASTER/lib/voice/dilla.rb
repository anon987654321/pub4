# frozen_string_literal: true

module Master
  module Voice
    module Dilla
      module_function

      def profile
        ProductionDna.producer(:j_dilla)
      end

      def chords(collection = nil)
        ProductionDna.chords_for(:j_dilla, collection)
      end

      def swing
        profile.fetch(:timing)
      end

      def lofi_preset
        ProductionDna.preset(:dilla_drum_bus)
      end

      def sonitex_preset
        ProductionDna.sonitex_preset_for(:dilla_drum_bus)
      end

      def brief
        timing = swing
        <<~TEXT.strip
        Dilla mode: #{profile.fetch(:philosophy)}.
        Timing: #{timing.fetch(:ppqn)} PPQN, #{timing.fetch(:swing_percent)}% swing pocket, #{timing.fetch(:bpm)} BPM.
        Nudge: hats #{timing.dig(:nudge, :hihats)}, snares #{timing.dig(:nudge, :snares)}, kicks #{timing.dig(:nudge, :kicks)}.
        Lo-fi chain: use Sonitex preset #{sonitex_preset}; low-pass samples, keep drums human, add sub support near 40Hz.
      TEXT
      end

      def council_brief
        brief
      rescue StandardError
        begin
          ProductionDna.brief
        rescue StandardError => e
          "Dilla production profile failed to load: #{e.message}."
        end
      end
    end
  end
end
