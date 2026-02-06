# frozen_string_literal: true

module MASTER
  module Interactive
    include Colors
    
    # Hover states (simulated with brackets)
    def hoverable(text)
      "[ #{text} ]"
    end
    
    # Feedback indicators
    def feedback(action, status)
      case status
      when :success then "#{MINT_GREEN}✓ #{action} completed#{RESET}"
      when :error then "#{RED}✗ #{action} failed#{RESET}"
      when :loading then "#{STEEL_BLUE}⟳ #{action} in progress#{RESET}"
      end
    end
    
    # Loading indicators
    def spinner(frame = 0)
      frames = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏]
      "#{STEEL_BLUE}#{frames[frame % frames.length]}#{RESET}"
    end
    
    # Focus indicators
    def focused(text)
      "#{STEEL_BLUE}▶ #{text}#{RESET}"
    end
    
    # Keyboard shortcuts
    def shortcut(key, description)
      "#{PEARL_GREY}#{key}#{RESET} #{description}"
    end
  end
end
