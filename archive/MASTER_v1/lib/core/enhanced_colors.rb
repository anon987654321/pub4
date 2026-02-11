# frozen_string_literal: true

# Legacy compatibility stub - colors now in cli.rb
# This file exists only to prevent LoadError on systems with old cached requires

module MASTER
  module EnhancedColors
    # All color constants moved to CLI class
    # See lib/cli.rb for C_RESET, C_BOLD, C_DIM, C_GREY, etc.
  end
end
