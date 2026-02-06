# frozen_string_literal: true

module MASTER
  class CLI
    module Constants
      module Config
        HISTORY_LIMIT = 100
        EASTER_EGG_CHANCE = 0.01
        UPTIME_THRESHOLD = 3600  # Show uptime after 1 hour
        COST_TIER_LOW = 0.01
        COST_TIER_MED = 0.10
        MAX_CODE_PREVIEW = 2000
        MAX_RESEARCH_PREVIEW = 500
        MAX_VIOLATION_PREVIEW = 200
        MAX_REASON_PREVIEW = 200
        MAX_RESPONSE_PREVIEW = 150
        INTERRUPT_TIMEOUT = 2.0  # Seconds to press Ctrl+C again to quit

        # Verbosity levels
        VERBOSITY = { low: 0, medium: 1, high: 2 }.freeze
      end
    end
  end
end
