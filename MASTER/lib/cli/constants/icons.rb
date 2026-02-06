# frozen_string_literal: true

module MASTER
  class CLI
    module Constants
      module Icons
        # Icon vocabulary - 5 symbols max, single meaning each
        ICON_OK   = "✓"
        ICON_ERR  = "✗"
        ICON_WARN = "!"
        ICON_ITEM = "·"
        ICON_FLOW = "→"

        # Spinner (ASCII, by prompt)
        SPINNER = %w[| / - \\].freeze
      end
    end
  end
end
