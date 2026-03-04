# frozen_string_literal: true

module Chamber
  class Review
    DEFAULT_SCORE = 0
    MIN_REVIEW_WORDS = 3
    WORD_SPLIT_REGEX = /\s+/

    attr_reader :record

    def initialize(record)
      @record = record
    end

    def self.for_chamber(chamber_id:)
      ReviewRecord.where(chamber_id: chamber_id).includes(:persona, :user)
    end

    def persona_vote(persona:, review_text:, weight: 1, min_words: MIN_REVIEW_WORDS)
      return DEFAULT_SCORE unless persona
      return DEFAULT_SCORE unless weight.to_i.positive?

      words = normalized_words(review_text)
      return DEFAULT_SCORE unless words.length >= min_words

      vote_for(persona: persona, words: words, weight: weight)
    rescue StandardError
      DEFAULT_SCORE
    end

    private

    def normalized_words(text)
      cleaned = text.to_s.strip
      return [] if cleaned.empty?

      cleaned.split(WORD_SPLIT_REGEX).map!(&:downcase)
    end

    def vote_for(persona:, words:, weight:)
      keywords = persona.keywords.to_a
      score = words.count { |word| keywords.include?(word) }
      (score * weight.to_f).round
    end
  end
end