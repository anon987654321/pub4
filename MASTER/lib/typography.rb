# frozen_string_literal: true

module MASTER
  module Typography
    # Bringhurst typography rules:
    # - Proper quotes (" " instead of " ")
    # - Em dashes (—) instead of double hyphens (--)
    # - Ellipsis (…) instead of three dots (...)
    # - 72-character line wrapping for readability

    def self.apply(text)
      result = text.dup
      
      # Smart quotes
      result.gsub!(/"([^"]+)"/, '"\1"')
      result.gsub!(/'([^']+)'/, ''\1'')
      
      # Em dashes
      result.gsub!(/--/, '—')
      result.gsub!(/\s-\s/, ' — ')
      
      # Ellipsis
      result.gsub!(/\.\.\./, '…')
      
      result
    end

    def self.wrap(text, width: 72)
      lines = []
      current_line = []
      current_length = 0
      
      text.split(/\s+/).each do |word|
        word_length = word.length
        
        if current_length + word_length + 1 > width && !current_line.empty?
          lines << current_line.join(' ')
          current_line = [word]
          current_length = word_length
        else
          current_line << word
          current_length += word_length + (current_line.length > 1 ? 1 : 0)
        end
      end
      
      lines << current_line.join(' ') unless current_line.empty?
      lines.join("\n")
    end

    def self.format(text, wrap: true)
      result = apply(text)
      wrap ? self.wrap(result) : result
    end
  end
end
