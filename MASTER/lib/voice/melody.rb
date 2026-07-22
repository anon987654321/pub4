# frozen_string_literal: true

module Master
  module Voice
    # Pentatonic phrase contours — DiffSinger/CoMelSinger-inspired melodic planning.
    module Melody
      PENTATONIC = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21].freeze
      RHYTHM = ["+2%", "+6%", "+4%", "+8%", "+3%"].freeze

      module_function

      def plan(text, emotion)
        phrases = text.to_s.split(/(?<=[.!?,;:])\s+/).map(&:strip).reject(&:empty?)
        phrases = [text.to_s.strip] if phrases.empty?
        arousal = emotion.dig(:scores, :arousal).to_f

        {
          mode: emotion.fetch(:mode, :melodic),
          base_pitch: arousal > 0.6 ? "+8Hz" : "+0Hz",
          phrases: build_phrase_plan(phrases, arousal),
        }
      end

      def pause_ms_for(index, arousal)
        return 0 if index.zero?
        arousal > 0.55 ? 90 : 140
      end

      def build_phrase_plan(phrases, arousal)
        phrases.each_with_index.map do |phrase, i|
          semitone = PENTATONIC[i % PENTATONIC.length]
          {
            text: phrase,
            rate: RHYTHM[i % RHYTHM.length],
            pitch: format("%+dHz", semitone * 7),
            semitone:,
            pause_ms: pause_ms_for(i, arousal),
          }
        end
      end
    end
  end
end
