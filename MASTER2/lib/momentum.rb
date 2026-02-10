# frozen_string_literal: true

module MASTER
  # Momentum - Track task progress and productivity metrics
  module Momentum
    extend self

    XP = {
      chat: 1,
      refactor: 5,
      evolve: 10,
      fix: 3,
      test: 2
    }.freeze

    LEVELS = [
      { xp: 0, title: "Novice" },
      { xp: 50, title: "Apprentice" },
      { xp: 150, title: "Journeyman" },
      { xp: 300, title: "Expert" },
      { xp: 500, title: "Master" }
    ].freeze

    def fresh
      {
        xp: 0,
        level: 1,
        streak: 0,
        achievements: []
      }
    end

    def state
      @state ||= fresh
    end

    def award(action)
      xp_gain = XP[action] || 1
      multiplier = streak_multiplier
      total_gain = (xp_gain * multiplier).to_i
      
      state[:xp] += total_gain
      state[:level] = calculate_level(state[:xp])
      
      { xp_gained: total_gain, total_xp: state[:xp], level: state[:level] }
    end

    def title
      LEVELS.reverse.find { |l| state[:xp] >= l[:xp] }&.[](:title) || "Novice"
    end

    def streak_multiplier
      case state[:streak]
      when 0..2 then 1.0
      when 3..6 then 1.2
      when 7..13 then 1.5
      else 2.0
      end
    end

    def track(action, result: nil)
      # Track action and update streak if successful
      if result&.ok? || result.nil?
        state[:streak] += 1
      else
        state[:streak] = 0
      end
      
      Result.ok(action: action, tracked: true)
    end

    def summary
      { 
        tasks_completed: state[:xp] / 5,
        streak: state[:streak],
        level: state[:level],
        title: title
      }
    end

    private

    def calculate_level(xp)
      LEVELS.count { |l| xp >= l[:xp] }
    end
  end
end
