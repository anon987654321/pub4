# frozen_string_literal: true

module MASTER
  module Typography
    def self.format(text)
      regions = split_regions(text)
      regions.map do |region|
        region[:code] ? region[:text] : typeset(region[:text])
      end.join
    end

    def self.split_regions(text)
      regions = []
      current_pos = 0
      in_code = false
      
      text.scan(/```.*?$/m).each_with_index do |match, _|
        match_pos = text.index(match, current_pos)
        
        # Add prose before code fence
        if match_pos > current_pos
          regions << { text: text[current_pos...match_pos], code: in_code }
        end
        
        # Toggle code mode
        in_code = !in_code
        
        # Find end of code block
        if in_code
          end_marker = text.index(/^```\s*$/m, match_pos + match.length)
          if end_marker
            code_end = end_marker + text[end_marker..].index("\n") + 1
            regions << { text: text[match_pos...code_end], code: true }
            current_pos = code_end
            in_code = false
          else
            regions << { text: text[match_pos..], code: true }
            current_pos = text.length
          end
        else
          regions << { text: match + "\n", code: false }
          current_pos = match_pos + match.length + 1
        end
      end
      
      # Add remaining text
      if current_pos < text.length
        regions << { text: text[current_pos..], code: in_code }
      end
      
      regions
    end

    def self.typeset(text)
      return text if text.strip.empty?
      
      # Smart quotes
      text = text.gsub(/"([^"]+)"/, '"\1"')
      
      # Em dashes
      text = text.gsub(/\s+--\s+/, ' — ')
      
      # Ellipsis
      text = text.gsub(/\.\.\./, '…')
      
      # Wrap prose
      wrap_prose(text)
    end

    def self.wrap_prose(text, width: 72)
      paragraphs = text.split(/\n\n+/)
      
      wrapped = paragraphs.map do |para|
        next para if para.strip.empty?
        
        words = para.split(/\s+/)
        lines = []
        current_line = []
        current_length = 0
        
        words.each do |word|
          word_length = word.length
          
          if current_length + word_length + current_line.length > width && !current_line.empty?
            lines << current_line.join(' ')
            current_line = [word]
            current_length = word_length
          else
            current_line << word
            current_length += word_length
          end
        end
        
        lines << current_line.join(' ') unless current_line.empty?
        lines.join("\n")
      end
      
      wrapped.join("\n\n")
    end
  end
end
