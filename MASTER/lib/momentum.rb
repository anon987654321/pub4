# frozen_string_literal: true

module MASTER
  # Momentum - gamification, streaks, achievements, XP system
  # Makes MASTER usage rewarding and tracks progress
  module Momentum
    extend self

    DATA_FILE = File.join(Paths.var, 'momentum.yml')

    # XP rewards per action
    XP_REWARDS = {
      chat: 5,
      scan: 10,
      refactor: 25,
      beautify: 15,
      bughunt: 30,
      commit: 20,
      push: 10,
      evolve: 50,
      chamber: 40,
      goal_complete: 100,
      task_complete: 15,
      streak_bonus: 10,      # Per day in streak
      first_of_day: 25,
      session_long: 50,      # 1+ hour session
      error_recovery: 20,    # Successfully recovered from error
      learning: 15           # Added to few-shot examples
    }.freeze

    # Level thresholds (cumulative XP)
    LEVELS = [
      0, 100, 300, 600, 1000, 1500, 2200, 3000, 4000, 5500,
      7500, 10000, 13000, 17000, 22000, 28000, 35000, 45000, 60000, 80000
    ].freeze

    LEVEL_TITLES = %w[
      Novice Apprentice Journeyman Adept Expert
      Veteran Master Grandmaster Legend Mythic
      Transcendent Eternal Cosmic Omniscient Divine
      Ascended Primordial Infinite Absolute Ultimate
    ].freeze

    # Achievement definitions
    ACHIEVEMENTS = {
      first_blood: { name: "First Blood", desc: "Complete your first task", check: ->(s) { s[:tasks_completed] >= 1 } },
      centurion: { name: "Centurion", desc: "Complete 100 tasks", check: ->(s) { s[:tasks_completed] >= 100 } },
      streak_3: { name: "Hat Trick", desc: "3-day streak", check: ->(s) { s[:max_streak] >= 3 } },
      streak_7: { name: "Weekly Warrior", desc: "7-day streak", check: ->(s) { s[:max_streak] >= 7 } },
      streak_30: { name: "Monthly Master", desc: "30-day streak", check: ->(s) { s[:max_streak] >= 30 } },
      refactor_10: { name: "Code Surgeon", desc: "Refactor 10 files", check: ->(s) { s[:refactors] >= 10 } },
      refactor_100: { name: "Architect", desc: "Refactor 100 files", check: ->(s) { s[:refactors] >= 100 } },
      bughunt_5: { name: "Bug Hunter", desc: "Hunt 5 bugs", check: ->(s) { s[:bughunts] >= 5 } },
      bughunt_50: { name: "Exterminator", desc: "Hunt 50 bugs", check: ->(s) { s[:bughunts] >= 50 } },
      commits_10: { name: "Committer", desc: "10 commits", check: ->(s) { s[:commits] >= 10 } },
      commits_100: { name: "Prolific", desc: "100 commits", check: ->(s) { s[:commits] >= 100 } },
      evolve_1: { name: "Self-Aware", desc: "First evolution", check: ->(s) { s[:evolves] >= 1 } },
      evolve_10: { name: "Transcendent", desc: "10 evolutions", check: ->(s) { s[:evolves] >= 10 } },
      chamber_1: { name: "Deliberator", desc: "First chamber session", check: ->(s) { s[:chambers] >= 1 } },
      night_owl: { name: "Night Owl", desc: "Work past midnight", check: ->(s) { s[:night_sessions] >= 1 } },
      early_bird: { name: "Early Bird", desc: "Work before 6am", check: ->(s) { s[:early_sessions] >= 1 } },
      marathon: { name: "Marathon", desc: "3+ hour session", check: ->(s) { s[:marathon_sessions] >= 1 } },
      budget_saver: { name: "Frugal", desc: "Complete 50 tasks under $1", check: ->(s) { s[:budget_tasks] >= 50 } },
      level_5: { name: "Rising Star", desc: "Reach level 5", check: ->(s) { s[:level] >= 5 } },
      level_10: { name: "Veteran", desc: "Reach level 10", check: ->(s) { s[:level] >= 10 } },
      level_20: { name: "Ultimate", desc: "Reach level 20", check: ->(s) { s[:level] >= 20 } }
    }.freeze

    class << self
      def load_state
        return default_state unless File.exist?(DATA_FILE)

        YAML.load_file(DATA_FILE, symbolize_names: true) rescue default_state
      end

      def save_state(state)
        FileUtils.mkdir_p(File.dirname(DATA_FILE))
        File.write(DATA_FILE, state.to_yaml)
      end

      def default_state
        {
          xp: 0,
          level: 1,
          streak: 0,
          max_streak: 0,
          last_active: nil,
          tasks_completed: 0,
          refactors: 0,
          bughunts: 0,
          commits: 0,
          evolves: 0,
          chambers: 0,
          chats: 0,
          night_sessions: 0,
          early_sessions: 0,
          marathon_sessions: 0,
          budget_tasks: 0,
          session_start: Time.now.to_i,
          achievements: [],
          total_cost: 0.0
        }
      end

      # Award XP for an action
      def award(action, multiplier: 1.0)
        state = load_state
        base_xp = XP_REWARDS[action] || 5
        xp = (base_xp * multiplier).round

        state[:xp] += xp
        old_level = state[:level]
        state[:level] = calculate_level(state[:xp])

        # Track action counts
        case action
        when :refactor then state[:refactors] += 1
        when :bughunt then state[:bughunts] += 1
        when :commit then state[:commits] += 1
        when :evolve then state[:evolves] += 1
        when :chamber then state[:chambers] += 1
        when :chat then state[:chats] += 1
        when :task_complete then state[:tasks_completed] += 1
        when :goal_complete then state[:tasks_completed] += 1
        end

        # Check time-based achievements
        hour = Time.now.hour
        state[:night_sessions] += 1 if hour >= 0 && hour < 5
        state[:early_sessions] += 1 if hour >= 5 && hour < 6

        # Check session length
        if state[:session_start]
          session_hours = (Time.now.to_i - state[:session_start]) / 3600.0
          state[:marathon_sessions] += 1 if session_hours >= 3
        end

        save_state(state)

        result = { xp: xp, total_xp: state[:xp], level: state[:level] }

        # Level up notification
        if state[:level] > old_level
          result[:level_up] = true
          result[:new_title] = level_title(state[:level])
          Dmesg.log("momentum0", parent: "level", message: "UP! #{state[:level]} - #{result[:new_title]}") rescue nil
        end

        # Check achievements
        new_achievements = check_achievements(state)
        if new_achievements.any?
          result[:achievements] = new_achievements
          new_achievements.each do |a|
            Dmesg.log("achievement0", parent: "momentum0", message: "#{a[:name]} - #{a[:desc]}") rescue nil
          end
        end

        result
      end

      # Update streak (call daily)
      def update_streak
        state = load_state
        today = Date.today.to_s

        if state[:last_active].nil?
          state[:streak] = 1
          state[:last_active] = today
        elsif state[:last_active] == today
          # Already active today, no change
        elsif state[:last_active] == (Date.today - 1).to_s
          # Consecutive day
          state[:streak] += 1
          state[:max_streak] = [state[:max_streak], state[:streak]].max
          state[:last_active] = today

          # Streak bonus XP
          bonus = state[:streak] * XP_REWARDS[:streak_bonus]
          state[:xp] += bonus

          Dmesg.log("streak0", parent: "momentum0", message: "#{state[:streak]} days! +#{bonus}xp") rescue nil
        else
          # Streak broken
          state[:streak] = 1
          state[:last_active] = today
        end

        save_state(state)
        state[:streak]
      end

      def calculate_level(xp)
        LEVELS.each_with_index do |threshold, idx|
          return idx if xp < threshold
        end
        LEVELS.size
      end

      def level_title(level)
        LEVEL_TITLES[[level - 1, LEVEL_TITLES.size - 1].min]
      end

      def xp_to_next_level(state = nil)
        state ||= load_state
        current_level = state[:level]
        return 0 if current_level >= LEVELS.size

        next_threshold = LEVELS[current_level] || LEVELS.last
        next_threshold - state[:xp]
      end

      def check_achievements(state)
        new_achievements = []

        ACHIEVEMENTS.each do |id, achievement|
          next if state[:achievements].include?(id.to_s)

          if achievement[:check].call(state)
            state[:achievements] << id.to_s
            new_achievements << { id: id, name: achievement[:name], desc: achievement[:desc] }
          end
        end

        save_state(state) if new_achievements.any?
        new_achievements
      end

      # Format status display
      def status_display
        state = load_state
        level = state[:level]
        title = level_title(level)
        xp = state[:xp]
        next_xp = xp_to_next_level(state)
        streak = state[:streak]
        achievements = state[:achievements].size

        progress = if level < LEVELS.size
          current_min = LEVELS[level - 1] || 0
          current_max = LEVELS[level] || LEVELS.last
          pct = ((xp - current_min).to_f / (current_max - current_min) * 100).round
          "#{pct}%"
        else
          "MAX"
        end

        bar_width = 20
        filled = (progress.to_f / 100 * bar_width).round
        bar = "█" * filled + "░" * (bar_width - filled)

        lines = []
        lines << "#{title} (Level #{level})"
        lines << "[#{bar}] #{progress} to next"
        lines << "#{xp} XP total | #{next_xp} XP needed"
        lines << "🔥 #{streak}-day streak" if streak > 0
        lines << "🏆 #{achievements}/#{ACHIEVEMENTS.size} achievements"

        lines.join("\n")
      end

      # Compact one-liner for prompt
      def prompt_badge
        state = load_state
        "L#{state[:level]}#{state[:streak] > 0 ? "🔥#{state[:streak]}" : ""}"
      end

      # List all achievements with status
      def list_achievements
        state = load_state
        earned = state[:achievements]

        lines = ACHIEVEMENTS.map do |id, a|
          status = earned.include?(id.to_s) ? "✓" : "○"
          "#{status} #{a[:name]}: #{a[:desc]}"
        end

        lines.join("\n")
      end
    end
  end
end
