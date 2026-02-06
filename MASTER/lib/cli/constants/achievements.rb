# frozen_string_literal: true

module MASTER
  class CLI
    module Constants
      module Achievements
        # Achievements
        ACHIEVEMENTS = {
          first_command: { name: "First Steps", desc: "Ran first command" },
          streak_5: { name: "Momentum", desc: "5 without error" },
          streak_25: { name: "Flow State", desc: "25 without error" },
          first_refactor: { name: "Craftsman", desc: "First refactor" },
          spent_1: { name: "Investor", desc: "Spent $1 on LLM" },
          commands_100: { name: "Centurion", desc: "100 commands" }
        }.freeze
      end
    end
  end
end
