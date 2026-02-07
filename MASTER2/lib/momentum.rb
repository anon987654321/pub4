# frozen_string_literal: true

module MASTER
  # Momentum - Gamification: XP, levels, streaks, achievements
  module Momentum
    extend self

    DATA_FILE = -> { File.join(Paths.var, 'momentum.yml') }

    XP = {
      chat: 5, refactor: 25, bughunt: 30, commit: 20,
      evolve: 50, chamber: 40, streak_bonus: 10,
      first_of_day: 25, session_long: 50
    }.freeze

    LEVELS = [0, 100, 300, 600, 1000, 1500, 2200, 3000, 4000, 5500,
              7500, 10000, 13000, 17000, 22000, 28000, 35000, 45000].freeze

    TITLES = %w[Novice Apprentice Journeyman Adept Expert Veteran Master
                Grandmaster Legend Mythic Transcendent Eternal].freeze

    ACHIEVEMENTS = {
      first_blood:  { name: "First Blood",    desc: "Complete first task",  check: ->(s) { s[:tasks] >= 1 } },
      centurion:    { name: "Centurion",      desc: "100 tasks",            check: ->(s) { s[:tasks] >= 100 } },
      streak_7:     { name: "Weekly Warrior", desc: "7-day streak",         check: ->(s) { s[:max_streak] >= 7 } },
      streak_30:    { name: "Monthly Master", desc: "30-day streak",        check: ->(s) { s[:max_streak] >= 30 } },
      refactor_10:  { name: "Code Surgeon",   desc: "Refactor 10 files",    check: ->(s) { s[:refactors] >= 10 } },
      evolve_1:     { name: "Self-Aware",     desc: "First evolution",      check: ->(s) { s[:evolves] >= 1 } },
      level_10:     { name: "Veteran",        desc: "Reach level 10",       check: ->(s) { s[:level] >= 10 } }
    }.freeze

    class << self
      def state
        @state ||= load_state
      end

      def fresh
        {
          xp: 0, level: 1, streak: 0, max_streak: 0, last_active: nil,
          tasks: 0, refactors: 0, evolves: 0, chambers: 0, chats: 0,
          session_start: Time.now.to_i, achievements: []
        }
      end

      def load_state
        require 'yaml'
        File.exist?(DATA_FILE.call) ? YAML.load_file(DATA_FILE.call, symbolize_names: true) : fresh
      rescue
        fresh
      end

      def save
        require 'yaml'
        FileUtils.mkdir_p(File.dirname(DATA_FILE.call))
        File.write(DATA_FILE.call, state.to_yaml)
      end

      def award(action, multiplier: 1.0)
        base = XP[action.to_sym] || 5
        gained = (base * multiplier * streak_multiplier).round

        state[:xp] += gained
        state[:tasks] += 1
        state[:"#{action}s"] = (state[:"#{action}s"] || 0) + 1

        check_level_up
        check_streak
        check_achievements
        save

        { xp_gained: gained, total_xp: state[:xp], level: state[:level], title: title }
      end

      def title
        TITLES[[state[:level] - 1, TITLES.size - 1].min]
      end

      def streak_multiplier
        [1.0 + (state[:streak] * 0.1), 2.0].min
      end

      private

      def check_level_up
        LEVELS.each_with_index do |threshold, idx|
          if state[:xp] >= threshold
            state[:level] = idx + 1
          end
        end
      end

      def check_streak
        today = Date.today.to_s
        if state[:last_active] == (Date.today - 1).to_s
          state[:streak] += 1
        elsif state[:last_active] != today
          state[:streak] = 1
        end
        state[:last_active] = today
        state[:max_streak] = [state[:max_streak], state[:streak]].max
      end

      def check_achievements
        ACHIEVEMENTS.each do |key, ach|
          next if state[:achievements].include?(key.to_s)
          if ach[:check].call(state)
            state[:achievements] << key.to_s
            UI.success("🏆 Achievement: #{ach[:name]} - #{ach[:desc]}") rescue nil
          end
        end
      end
    end
  end
end
