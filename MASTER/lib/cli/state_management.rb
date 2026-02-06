# frozen_string_literal: true

module MASTER
  class CLI
    module StateManagement
      # Load command history from file
      def load_history
        return unless File.exist?(HISTORY_FILE)

        File.readlines(HISTORY_FILE).last(HISTORY_LIMIT).each do |line|
          Readline::HISTORY.push(line.chomp)
        end
      rescue StandardError
        # Ignore history errors
      end

      # Save command history to file
      def save_history
        File.open(HISTORY_FILE, 'a') do |f|
          Readline::HISTORY.to_a.last(HISTORY_LIMIT).each { |line| f.puts(line) }
        end
      rescue StandardError
        # Ignore history errors
      end

      # Load persistent state (achievements, favorites, aliases, etc.)
      def load_state
        return unless File.exist?(STATE_FILE)

        data = JSON.parse(File.read(STATE_FILE), symbolize_names: true)
        @achievements = data[:achievements] || []
        @favorites = data[:favorites] || []
        @aliases = data[:aliases] || {}
        @command_count = data[:command_count] || 0
        @total_cost = data[:total_cost] || 0.0
      rescue StandardError
        # Fresh state
      end

      # Save persistent state to file
      def save_state
        FileUtils.mkdir_p(Paths.var)
        File.write(STATE_FILE, JSON.pretty_generate({
          achievements: @achievements,
          favorites: @favorites,
          aliases: @aliases,
          command_count: @command_count,
          total_cost: @total_cost
        }))
      rescue StandardError
        # Ignore save errors
      end

      # Emergency save on crashes or interrupts
      def emergency_save
        save_state
        save_history
        @llm.clear_history rescue nil
      rescue StandardError
        # Best effort
      end

      # Setup crash recovery and signal handlers
      def setup_crash_recovery
        # Double Ctrl+C to quit (first one just warns)
        trap('INT') do
          now = Time.now
          if @last_interrupt && (now - @last_interrupt) < INTERRUPT_TIMEOUT
            puts "\n#{C_DIM}Exiting...#{C_RESET}"
            emergency_save
            exit(0)
          else
            @last_interrupt = now
            puts "\n#{C_YELLOW}Press Ctrl+C again within #{INTERRUPT_TIMEOUT.to_i}s to quit#{C_RESET}"
          end
        end

        # Other signals still exit immediately
        %w[TERM HUP].each do |sig|
          trap(sig) do
            emergency_save
            exit(1)
          end
        end

        # Auto-save on unhandled exceptions
        at_exit { emergency_save }
      end

      # Check and unlock achievements based on current stats
      def check_achievements
        unlock(:first_command) if @command_count == 1
        unlock(:streak_5) if @streak == 5
        unlock(:streak_25) if @streak == 25
        unlock(:commands_100) if @command_count == 100
        unlock(:spent_1) if @total_cost >= 1.0 && !@achievements.include?(:spent_1)
      end

      # Unlock an achievement and notify user
      def unlock(key)
        return if @achievements.include?(key)

        @achievements << key
        a = ACHIEVEMENTS[key]
        puts "#{C_YELLOW}★ #{a[:name]}#{C_RESET} — #{a[:desc]}"
        beep
      end

      # Terminal bell for notifications
      def beep
        print "\a" # Terminal bell
      end
    end
  end
end
