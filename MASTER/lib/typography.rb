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
      
      # Find all code fence pairs
      while current_pos < text.length
        # Find next code fence start
        fence_start = text.index(/^```/m, current_pos)
        
        if fence_start.nil?
          # No more code blocks, add remaining as prose
          regions << { text: text[current_pos..], code: false } if current_pos < text.length
          break
        end
        
        # Add prose before code fence
        if fence_start > current_pos
          regions << { text: text[current_pos...fence_start], code: false }
        end
        
        # Find the end of this code block
        fence_end = text.index(/^```\s*$/m, fence_start + 3)
        
        if fence_end
          # Include the closing fence
          fence_end_line = text.index("\n", fence_end)
          fence_end_line = text.length if fence_end_line.nil?
          regions << { text: text[fence_start..fence_end_line], code: true }
          current_pos = fence_end_line + 1
        else
          # No closing fence, treat rest as code
          regions << { text: text[fence_start..], code: true }
          break
        end
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
