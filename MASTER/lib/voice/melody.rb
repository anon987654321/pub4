# frozen_string_literal: true

require_relative "language"

module Master
  module Voice
    # Phrase segmentation and inter-phrase rests, plus the pentatonic contour that
    # sits on top of them for lyrical text (DiffSinger/CoMelSinger-inspired).
    #
    # Those are two different things and they used to be one. Segmentation and
    # rests are rhythm, which every utterance wants; the pentatonic pitch targets
    # are a stylistic mode that only lyrical text should get. Because
    # build_phrase_plan always attached both, the whole plan sat behind
    # Transcendent's melodic_threshold and ordinary speech was rendered as one
    # Edge call with one rate and one pitch, start to finish. `melodic: false`
    # keeps the phrases and the rests and drops the contour, so a phrase inherits
    # the resolved rate/pitch through Engines.synthesize_phrase_parts' fetch
    # defaults.
    module Melody
      PENTATONIC = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21].freeze
      RHYTHM = ["+2%", "+6%", "+4%", "+8%", "+3%"].freeze

      # Each phrase is its own Edge round trip, so segmentation is also a fan-out
      # multiplier on a 1 vCPU box. Past this many, trailing clauses are merged
      # back into the last phrase rather than adding calls.
      MAX_PHRASES = 6

      module_function

      def plan(text, emotion, melodic: true, languages: nil)
        phrases = segment(text)
        arousal = emotion.dig(:scores, :arousal).to_f

        {
          mode: emotion.fetch(:mode, :melodic),
          melodic:,
          base_pitch: arousal > 0.6 ? "+8Hz" : "+0Hz",
          phrases: build_phrase_plan(phrases, arousal, melodic:, languages:),
        }
      end

      def segment(text)
        phrases = text.to_s.split(/(?<=[.!?,;:])\s+/).map(&:strip).reject(&:empty?)
        return [text.to_s.strip] if phrases.empty?
        return phrases if phrases.length <= MAX_PHRASES

        head = phrases.first(MAX_PHRASES - 1)
        head + [phrases.drop(MAX_PHRASES - 1).join(" ")]
      end

      def pause_ms_for(index, arousal)
        return 0 if index.zero?
        arousal > 0.55 ? 90 : 140
      end

      def build_phrase_plan(phrases, arousal, melodic: true, languages: nil)
        phrases.each_with_index.map do |phrase, i|
          entry = { text: phrase, pause_ms: pause_ms_for(i, arousal) }
          entry = entry.merge(voice_for(phrase, languages)) if languages
          next entry unless melodic

          semitone = PENTATONIC[i % PENTATONIC.length]
          entry.merge(rate: RHYTHM[i % RHYTHM.length], pitch: format("%+dHz", semitone * 7), semitone:)
        end
      end

      # `languages` is the map of detected language to registered voice key, so
      # the caller owns which voices are in play and this owns only the split.
      # A phrase with no entry carries no :voice and inherits the resolved one
      # through Engines.synthesize_phrase_parts' fetch default.
      def voice_for(phrase, languages)
        key = languages[Language.detect(phrase)]
        key ? { voice: key, language: Language.detect(phrase) } : {}
      end
    end
  end
end
