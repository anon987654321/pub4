# frozen_string_literal: true

module MASTER
  module Colors
    RESET = "[0m"
    
    # Neutral blue-grey-mint palette
    SLATE_BLUE = "[38;2;100;116;139m"    # Primary text
    SAGE_GREY = "[38;2;139;149;158m"     # Secondary text
    MINT_GREEN = "[38;2;152;195;181m"    # Success/positive
    STEEL_BLUE = "[38;2;79;109;122m"     # Interactive elements
    PEARL_GREY = "[38;2;176;190;197m"    # Subtle details
    
    # Semantic aliases
    PRIMARY = SLATE_BLUE
    SECONDARY = SAGE_GREY
    SUCCESS = MINT_GREEN
    INTERACTIVE = STEEL_BLUE
    SUBTLE = PEARL_GREY
    
    def primary(text) = "#{PRIMARY}#{text}#{RESET}"
    def secondary(text) = "#{SECONDARY}#{text}#{RESET}"
    def success(text) = "#{SUCCESS}#{text}#{RESET}"
    def interactive(text) = "#{INTERACTIVE}#{text}#{RESET}"
    def subtle(text) = "#{SUBTLE}#{text}#{RESET}"
  end
end
