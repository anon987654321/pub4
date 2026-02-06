# frozen_string_literal: true

module MASTER
  module Strunk
    FORBIDDEN_PHRASES = [
      "I would", "In theory", "Hypothetically", "In my opinion",
      "I think", "I believe", "It seems", "Perhaps", "Maybe",
      "Kind of", "Sort of", "Actually", "Basically", "Literally"
    ].freeze

    REPLACEMENTS = {
      /\bvery\s+(\w+)/ => '\1',
      /\bin order to\b/ => 'to',
      /\bdue to the fact that\b/ => 'because',
      /\bat this point in time\b/ => 'now',
      /\bfor the purpose of\b/ => 'for',
      /\bin the event that\b/ => 'if',
      /\bprior to\b/ => 'before',
      /\bsubsequent to\b/ => 'after'
    }.freeze

    def self.compress(text)
      result = text.dup
      
      # Remove forbidden phrases
      FORBIDDEN_PHRASES.each do |phrase|
        result.gsub!(/\b#{Regexp.escape(phrase)}\b/i, '')
      end
      
      # Apply replacements for needless words
      REPLACEMENTS.each do |pattern, replacement|
        result.gsub!(pattern, replacement)
      end
      
      # Convert passive to active voice hints (basic)
      result.gsub!(/\bwas (\w+ed) by\b/, '\1')
      
      # Remove duplicate spaces
      result.gsub!(/\s+/, ' ')
      result.strip
    end

    def self.density(text)
      words = text.split.length
      return 0 if words.zero?
      
      # Calculate information density based on unique words, sentence structure
      unique_words = text.split.uniq.length
      avg_word_length = text.split.map(&:length).sum.to_f / words
      
      # Higher density = more unique words, longer average word length
      (unique_words.to_f / words) * (avg_word_length / 5.0)
    end
  end
end
