# frozen_string_literal: true

module MASTER
  module Hierarchy
    include Colors
    include Typography
    
    # Information layers
    def primary(text)
      "#{SLATE_BLUE}#{BOLD}#{text}#{RESET}"
    end
    
    def secondary(text)
      "#{SAGE_GREY}#{text}#{RESET}"
    end
    
    def tertiary(text)
      "#{PEARL_GREY}#{text}#{RESET}"
    end
    
    # Spacing scale
    SPACING = {
      xs: " " * 2,   # 8px equivalent
      sm: " " * 4,   # 16px equivalent  
      md: " " * 6,   # 24px equivalent
      lg: " " * 8    # 32px equivalent
    }.freeze
    
    # Indentation for relationships
    def indent(text, level = 1)
      prefix = SPACING[:sm] * level
      text.lines.map { |line| "#{prefix}#{line}" }.join
    end
    
    # Proximity grouping
    def group(items, spacing = :sm)
      items.join(SPACING[spacing])
    end
  end
end
