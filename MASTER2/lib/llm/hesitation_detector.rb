# frozen_string_literal: true

module Llm
  class HesitationDetector
    DEFAULT_MIN_HESITATION_COUNT = 2
    DEFAULT_MIN_HESITATION_RATIO = 0.02
    DEFAULT_MIN_TEXT_LENGTH = 30

    HESITATION_TOKENS = %w[
      um
      uh
      erm
      er
      hmm
      hmmm
      ah
      eh
      like
      basically
      literally
      actually
      so
      well
    ].freeze

    HESITATION_REGEX = /
      (?<![a-z])
      (?:#{HESITATION_TOKENS.map { |t| Regexp.escape(t) }.join('|')})
      (?![a-z])
    /ix.freeze

    attr_reader :min_hesitation_count, :min_hesitation_ratio, :min_text_length

    def initialize(
      min_hesitation_count: DEFAULT_MIN_HESITATION_COUNT,
      min_hesitation_ratio: DEFAULT_MIN_HESITATION_RATIO,
      min_text_length: DEFAULT_MIN_TEXT_LENGTH
    )
      @min_hesitation_count = min_hesitation_count
      @min_hesitation_ratio = min_hesitation_ratio
      @min_text_length = min_text_length
    end

    def detect(text)
      normalized = normalize_text(text)
      return result(false, 0, 0, 0.0) if normalized.length < min_text_length

      tokens = normalized.scan(/[[:alpha:]]+/)
      token_count = tokens.length
      return result(false, 0, 0, 0.0) if token_count.zero?

      hesitation_count = normalized.scan(HESITATION_REGEX).length
      ratio = hesitation_count.to_f / token_count

      hesitant =
        hesitation_count >= min_hesitation_count ||
        ratio >= min_hesitation_ratio

      result(hesitant, hesitation_count, token_count, ratio)
    end

    private

    def normalize_text(text)
      text.to_s
          .downcase
          .gsub(/\s+/, ' ')
          .strip
    end

    def result(hesitant, hesitation_count, token_count, ratio)
      {
        hesitant: hesitant,
        hesitation_count: hesitation_count,
        token_count: token_count,
        hesitation_ratio: ratio
      }
    end
  end
end