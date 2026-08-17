# frozen_string_literal: true

module Master
  module Voice
    # Which language a phrase is in, for phrase-level voice selection.
    #
    # Deliberately a small heuristic and not a classifier: the phrases are short
    # and the only decision it feeds is which of two registered Edge voices reads
    # a clause. Guessing :en is free -- that is the current behaviour for
    # everything -- so the detector is built to be certain before it says :nb.
    #
    # Certainty comes from two signals, either of which is decisive. A
    # Norwegian-only letter, or a word that is not an English word at all.
    #
    # MARKERS earns its threshold of one by what it excludes rather than by
    # counting. "for", "en", "sin", "over", "under", "man" and "de" are all
    # ordinary Norwegian and all also English, so they are absent; so is "vi",
    # which is an editor here more often than a pronoun. What is left cannot
    # appear in an English sentence, so a second hit would add nothing but a
    # missed short clause -- and short clauses are exactly what phrase-level
    # detection exists for.
    module Language
      NORDIC_LETTERS = /[æøåÆØÅ]/
      MARKERS = %w[
        og ikke ikkje jeg det som til med har være er
        kan skal dette denne noen mye veldig fordi eller
        hvis hvor når dem seg sitt disse etter mellom
        ser gjør går kommer riktig ferdig faktisk
      ].freeze
      MARKER_RE = Regexp.new("(?<![\\w-])(#{MARKERS.join('|')})(?![\\w-])", Regexp::IGNORECASE)

      module_function

      def detect(text)
        body = text.to_s
        return :nb if body.match?(NORDIC_LETTERS)

        body.match?(MARKER_RE) ? :nb : :en
      end

      def norwegian?(text) = detect(text) == :nb
    end
  end
end
