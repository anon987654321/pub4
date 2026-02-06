# frozen_string_literal: true

module MASTER
  class CLI
    module Constants
      module Colors
        # ANSI colors - dark blue / light blue theme on black
        C_RESET  = "\e[0m"
        C_RED    = "\e[31m"              # Error only
        C_GREEN  = "\e[32m"              # Success only
        C_YELLOW = "\e[33m"              # Warning only
        C_DIM    = "\e[2m"               # Secondary/metadata
        C_BOLD   = "\e[1m"               # Primary emphasis
        C_ITALIC = "\e[3m"               # Secondary emphasis

        # Blue theme
        C_DARK_BLUE  = "\e[38;5;24m"     # Dark blue - primary text
        C_LIGHT_BLUE = "\e[38;5;75m"     # Light blue - accent/highlight
        C_CYAN       = "\e[38;5;75m"     # Alias for light blue
        C_GREY       = "\e[38;5;24m"     # Dark blue as main text
        C_MINT       = "\e[38;5;75m"     # Light blue for exits
      end
    end
  end
end
