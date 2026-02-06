#!/usr/bin/env ruby
# frozen_string_literal: true

module MASTER
  # Strunk & White text compression
  # Omit needless words, use active voice, achieve information density
  module Strunk
    FORBIDDEN_PHRASES = [
      /\b(I would|I could|I should|I might|I may)\b/i,
      /\b(In theory|Theoretically|Hypothetically)\b/i,
      /\b(sort of|kind of|basically|actually|literally)\b/i,
      /\b(very|really|quite|rather|somewhat)\b/i,
      /\b(In my opinion|I think that|I believe that)\b/i,
      /\b(In order to)\b/i,  # just "to"
      /\b(due to the fact that)\b/i,  # just "because"
      /\b(at this point in time)\b/i,  # just "now"
      /\b(for the purpose of)\b/i,  # just "to"
    ].freeze

    PASSIVE_INDICATORS = [
      /\b(is|are|was|were|be|being|been)\s+\w+ed\b/,
      /\b(has|have|had)\s+been\s+\w+ed\b/,
    ].freeze

    REPLACEMENTS = {
      'in order to' => 'to',
      'due to the fact that' => 'because',
      'at this point in time' => 'now',
      'for the purpose of' => 'to',
      'in the event that' => 'if',
      'a number of' => 'several',
      'at the present time' => 'now',
      'in the near future' => 'soon',
    }.freeze

    class << self
      # Compress text using Strunk & White principles
      def compress(text)
        return text if text.nil? || text.empty?
        
        result = text.dup
        
        # Apply replacements
        REPLACEMENTS.each do |wordy, concise|
          result.gsub!(/\b#{Regexp.escape(wordy)}\b/i, concise)
        end
        
        # Remove forbidden phrases
        FORBIDDEN_PHRASES.each do |pattern|
          result.gsub!(pattern, '')
        end
        
        # Clean up whitespace
        result.gsub!(/\s+/, ' ')
        result.strip!
        
        result
      end

      # Calculate information density (ratio of meaningful words to total words)
      # Target: > 0.7
      def density(text)
        return 0.0 if text.nil? || text.empty?
        
        words = text.split(/\s+/)
        return 0.0 if words.empty?
        
        # Count non-filler words
        filler_words = %w[the a an and or but is are was were be been being has have had do does did will would should could may might must can of in on at to for with by from]
        meaningful = words.count { |w| !filler_words.include?(w.downcase) }
        
        meaningful.to_f / words.length
      end

      # Check for passive voice
      def passive?(text)
        PASSIVE_INDICATORS.any? { |pattern| text.match?(pattern) }
      end

      # Convert passive to active (simple heuristic)
      def activate(text)
        return text unless passive?(text)
        
        # This is a simplified conversion
        # Real implementation would need NLP
        text.gsub(/\b(is|are|was|were)\s+(\w+ed)\s+by\s+(\w+)/) { "#{$3} #{$2.sub(/ed$/, '')}" }
      end

      # Full compression pipeline
      def process(text)
        result = compress(text)
        result = activate(result) if passive?(result)
        
        {
          text: result,
          density: density(result),
          compressed: result != text,
          original_length: text.length,
          final_length: result.length,
          reduction: ((text.length - result.length).to_f / text.length * 100).round(1)
        }
      end
    end
  end
end
