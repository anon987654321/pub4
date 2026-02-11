# frozen_string_literal: true

module MASTER
  # Momentum: XP, levels, streaks, achievements - gamification that rewards consistency
  module Momentum
    extend self

    DATA_FILE = File.join(Paths.var, 'momentum.yml')

    XP = { chat: 5, scan: 10, refactor: 25, beautify: 15, bughunt: 30, commit: 20,
           push: 10, evolve: 50, chamber: 40, goal_complete: 100, task_complete: 15,
           streak_bonus: 10, first_of_day: 25, session_long: 50, error_recovery: 20, learning: 15 }.freeze

    LEVELS = [0, 100, 300, 600, 1000, 1500, 2200, 3000, 4000, 5500,
              7500, 10000, 13000, 17000, 22000, 28000, 35000, 45000, 60000, 80000].freeze

    TITLES = %w[Novice Apprentice Journeyman Adept Expert Veteran Master
                Grandmaster Legend Mythic Transcendent Eternal Cosmic
                Omniscient Divine Ascended Primordial Infinite Absolute Ultimate].freeze

    ACHIEVEMENTS = {
      first_blood:   ["First Blood",      "Complete first task",    ->(s) { s[:tasks] >= 1 }],
      centurion:     ["Centurion",        "100 tasks",              ->(s) { s[:tasks] >= 100 }],
      streak_3:      ["Hat Trick",        "3-day streak",           ->(s) { s[:max_streak] >= 3 }],
      streak_7:      ["Weekly Warrior",   "7-day streak",           ->(s) { s[:max_streak] >= 7 }],
      streak_30:     ["Monthly Master",   "30-day streak",          ->(s) { s[:max_streak] >= 30 }],
      refactor_10:   ["Code Surgeon",     "Refactor 10 files",      ->(s) { s[:refactors] >= 10 }],
      refactor_100:  ["Architect",        "Refactor 100 files",     ->(s) { s[:refactors] >= 100 }],
      bughunt_5:     ["Bug Hunter",       "Hunt 5 bugs",            ->(s) { s[:bughunts] >= 5 }],
      bughunt_50:    ["Exterminator",     "Hunt 50 bugs",           ->(s) { s[:bughunts] >= 50 }],
      commits_10:    ["Committer",        "10 commits",             ->(s) { s[:commits] >= 10 }],
      commits_100:   ["Prolific",         "100 commits",            ->(s) { s[:commits] >= 100 }],
      evolve_1:      ["Self-Aware",       "First evolution",        ->(s) { s[:evolves] >= 1 }],
      evolve_10:     ["Transcendent",     "10 evolutions",          ->(s) { s[:evolves] >= 10 }],
      chamber_1:     ["Deliberator",      "First chamber",          ->(s) { s[:chambers] >= 1 }],
      night_owl:     ["Night Owl",        "Work past midnight",     ->(s) { s[:nights] >= 1 }],
      early_bird:    ["Early Bird",       "Work before 6am",        ->(s) { s[:early] >= 1 }],
      marathon:      ["Marathon",         "3+ hour session",        ->(s) { s[:marathons] >= 1 }],
      level_5:       ["Rising Star",      "Reach level 5",          ->(s) { s[:level] >= 5 }],
      level_10:      ["Veteran",          "Reach level 10",         ->(s) { s[:level] >= 10 }],
      level_20:      ["Ultimate",         "Reach level 20",         ->(s) { s[:level] >= 20 }]
    }.freeze

    class << self
      def state
        @state ||= File.exist?(DATA_FILE) ? (YAML.load_file(DATA_FILE, symbolize_names: true) rescue fresh) : fresh
      end

      def fresh
        { xp: 0, level: 1, streak: 0, max_streak: 0, last_active: nil, tasks: 0,
          refactors: 0, bughunts: 0, commits: 0, evolves: 0, chambers: 0, chats: 0,
          nights: 0, early: 0, marathons: 0, session_start: Time.now.to_i, achievements: [] }
      end

      def save
        FileUtils.mkdir_p(File.dirname(DATA_FILE))
        File.write(DATA_FILE, state.to_yaml)
      end

      def award(action, multiplier: 1.0)
        pts = ((XP[action] || 5) * multiplier).round
        state[:xp] += pts
        old_lvl = state[:level]
        state[:level] = LEVELS.index { |t| state[:xp] < t } || LEVELS.size

        # Track counts
        state[:refactors] += 1 if action == :refactor
        state[:bughunts] += 1 if action == :bughunt
        state[:commits] += 1 if action == :commit
        state[:evolves] += 1 if action == :evolve
        state[:chambers] += 1 if action == :chamber
        state[:tasks] += 1 if %i[task_complete goal_complete].include?(action)

        # Time achievements
        h = Time.now.hour
        state[:nights] += 1 if h >= 0 && h < 5
        state[:early] += 1 if h >= 5 && h < 6
        state[:marathons] += 1 if state[:session_start] && (Time.now.to_i - state[:session_start]) >= 10800

        save
        result = { xp: pts, total: state[:xp], level: state[:level] }

        if state[:level] > old_lvl
          result[:level_up] = TITLES[[state[:level] - 1, TITLES.size - 1].min]
          Dmesg.log("momentum0", parent: "level", message: "UP! L#{state[:level]} #{result[:level_up]}") rescue nil
        end

        (new_ach = check_achievements).each { |a| Dmesg.log("achievement0", message: a) rescue nil }
        result[:achievements] = new_ach if new_ach.any?
        result
      end

      def update_streak
        today = Date.today.to_s
        if state[:last_active].nil?
          state[:streak] = 1
        elsif state[:last_active] == today
          # already counted
        elsif state[:last_active] == (Date.today - 1).to_s
          state[:streak] += 1
          state[:max_streak] = [state[:max_streak], state[:streak]].max
          state[:xp] += state[:streak] * XP[:streak_bonus]
          Dmesg.log("streak0", message: "#{state[:streak]} days! +#{state[:streak] * XP[:streak_bonus]}xp") rescue nil
        else
          state[:streak] = 1
        end
        state[:last_active] = today
        save
        state[:streak]
      end

      def check_achievements
        earned = []
        ACHIEVEMENTS.each do |id, (name, desc, check)|
          next if state[:achievements].include?(id.to_s)
          if check.call(state)
            state[:achievements] << id.to_s
            earned << "#{name}: #{desc}"
          end
        end
        save if earned.any?
        earned
      end

      def title(lvl = state[:level])
        TITLES[[lvl - 1, TITLES.size - 1].min]
      end

      def xp_needed
        return 0 if state[:level] >= LEVELS.size
        (LEVELS[state[:level]] || LEVELS.last) - state[:xp]
      end

      def status_display
        pct = state[:level] < LEVELS.size ? ((state[:xp] - (LEVELS[state[:level] - 1] || 0)).to_f / ((LEVELS[state[:level]] || 1) - (LEVELS[state[:level] - 1] || 0)) * 100).round : 100
        bar = "█" * (pct / 5) + "░" * (20 - pct / 5)
        [
          "#{title} (L#{state[:level]})",
          "[#{bar}] #{pct}%",
          "#{state[:xp]} XP | #{xp_needed} to next",
          state[:streak] > 0 ? "🔥 #{state[:streak]}-day streak" : nil,
          "🏆 #{state[:achievements].size}/#{ACHIEVEMENTS.size}"
        ].compact.join("\n")
      end

      def badge
        "L#{state[:level]}#{state[:streak] > 0 ? "🔥#{state[:streak]}" : ""}"
      end

      def list_achievements
        ACHIEVEMENTS.map { |id, (n, d, _)| "#{state[:achievements].include?(id.to_s) ? '✓' : '○'} #{n}: #{d}" }.join("\n")
      end
    end
  end
end
