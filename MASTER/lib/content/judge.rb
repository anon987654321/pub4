# frozen_string_literal: true

module Master
  module Content
    # The judge: sends work back until it is publishable. A mechanical rubric
    # first — measures a stranger can re-run — then, when the runtime carries
    # an agent, the council's critique can harden the verdict. The mechanical
    # rubric alone decides; the council only sharpens the notes.
    class Judge
      MIN_WORDS = 220
      PUBLISH_SCORE = 7.0

      Rubric = Struct.new(:clarity, :structure, :specificity, :completeness, keyword_init: true) do
        def score = (clarity + structure + specificity + completeness) / 4.0
      end

      def initialize(min_words: MIN_WORDS, publish_score: PUBLISH_SCORE)
        @min_words = min_words
        @publish_score = publish_score
      end

      # Returns [verdict, notes]; verdict is :publish or :revise.
      def judge(card)
        rubric = rubric_for(card)
        notes = notes_for(card, rubric)
        if rubric.score >= @publish_score && notes.empty?
          [:publish, []]
        else
          [:revise, notes]
        end
      end

      private

      def rubric_for(card)
        body = card.body.to_s
        words = body.split(/\s+/).reject(&:empty?)
        headings = body.scan(/^#{Regexp.escape("#")}+\s+\S/).size
        concrete = body.scan(/\b\d+(\.\d+)?\b|\b[A-Z][a-z]+[A-Z]\w*|`[^`]+`|\*[^*]+\*/).size
        Rubric.new(
          clarity: words.size.between?(@min_words, 6_000) ? 8 : (words.size < @min_words ? 4 : 6),
          structure: words.size < @min_words ? 4 : (headings >= (words.size / 500.0).ceil ? 8 : 5),
          specificity: (concrete.to_f / [words.size, 1].max * 100).clamp(0, 12),
          completeness: placeholder?(body) ? 3 : 8,
        )
      end

      def notes_for(card, rubric)
        words = card.body.to_s.split(/\s+/).reject(&:empty?).size
        notes = []
        notes << "thin: #{words} words under the #{@min_words} a stranger needs" if words < @min_words
        notes << "placeholder text must go (TODO/lorem)" if placeholder?(card.body)
        notes << "add headings; a reader cannot navigate what they cannot scan" if rubric.structure < 6 && words >= @min_words
        notes << "be specific: name numbers, code or examples a reader can act on" if rubric.specificity < 3
        notes
      end

      def placeholder?(body)
        body.match?(/\bTBD\b|\bTODO\b|lorem ipsum/i)
      end
    end
  end
end
