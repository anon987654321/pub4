#!/usr/bin/env ruby
# frozen_string_literal: true

module MASTER
  # Bringhurst typography formatting
  # Proper quotes, em dashes, 72-char lines, no widows/orphans
  module Typography
    class << self
      # Format text with proper typography
      def format(text, width: 72)
        return text if text.nil? || text.empty?
        
        result = text.dup
        result = smart_quotes(result)
        result = em_dashes(result)
        result = ellipses(result)
        result = wrap_lines(result, width)
        result
      end

      # Convert straight quotes to smart quotes
      def smart_quotes(text)
        # Opening double quote
        text.gsub!(/(\s|^)"(\w)/, '\1"\2')
        # Closing double quote
        text.gsub!(/(\w)"(\s|$|[,.!?;:])/, '\1"\2')
        
        # Opening single quote
        text.gsub!(/(\s|^)'(\w)/, '\1'\2')
        # Closing single quote
        text.gsub!(/(\w)'(\s|$|[,.!?;:])/, '\1'\2')
        
        text
      end

      # Convert double hyphens to em dashes
      def em_dashes(text)
        text.gsub(/--/, '—')
      end

      # Convert three dots to ellipsis
      def ellipses(text)
        text.gsub(/\.\.\./, '…')
      end

      # Wrap lines to specified width
      # Avoid widows and orphans
      def wrap_lines(text, width)
        paragraphs = text.split(/\n\n+/)
        
        paragraphs.map do |para|
          words = para.split(/\s+/)
          lines = []
          current_line = []
          current_length = 0
          
          words.each do |word|
            word_length = word.length
            
            if current_length + word_length + current_line.length > width
              lines << current_line.join(' ')
              current_line = [word]
              current_length = word_length
            else
              current_line << word
              current_length += word_length
            end
          end
          
          lines << current_line.join(' ') unless current_line.empty?
          
          # Avoid orphans (single word on last line)
          if lines.length > 1 && lines.last.split.length == 1
            # Move one word from previous line to last line
            last_line_words = lines[-2].split
            if last_line_words.length > 2
              moved_word = last_line_words.pop
              lines[-2] = last_line_words.join(' ')
              lines[-1] = "#{moved_word} #{lines[-1]}"
            end
          end
          
          lines.join("\n")
        end.join("\n\n")
      end

      # Format as dmesg-style message
      # Example: master0: booted in 0.3s
      def dmesg(component, message)
        "master#{component}: #{message}"
      end

      # Format table data (for use with tty-table)
      def table(headers, rows)
        require 'tty-table'
        table = TTY::Table.new(headers, rows)
        table.render(:unicode)
      rescue LoadError
        # Fallback if tty-table not available
        ([headers] + rows).map { |row| row.join(' | ') }.join("\n")
      end

      # Format box (for use with tty-box)
      def box(content, title: nil)
        require 'tty-box'
        TTY::Box.frame(content, title: title, padding: 1, border: :thick)
      rescue LoadError
        # Fallback if tty-box not available
        lines = content.split("\n")
        width = lines.map(&:length).max + 4
        border = '+' + '-' * (width - 2) + '+'
        
        result = [border]
        result << "| #{title.center(width - 4)} |" if title
        result << border if title
        lines.each { |line| result << "| #{line.ljust(width - 4)} |" }
        result << border
        result.join("\n")
      end
    end
  end
end
