# frozen_string_literal: true

# Visual feedback for terminal UI
module MASTER
  module Unified
    class MoodIndicator
      MOODS = {
        idle: { color: :white, icon: "○", description: "Waiting" },
        thinking: { color: :cyan, icon: "◐", description: "Thinking" },
        working: { color: :yellow, icon: "◑", description: "Working" },
        success: { color: :green, icon: "●", description: "Success" },
        error: { color: :red, icon: "✗", description: "Error" }
      }.freeze

      attr_reader :current_mood

      def initialize(output: $stdout)
        @output = output
        @current_mood = :idle
        @colors = load_colors
      end

      def set(mood)
        return unless MOODS.key?(mood)
        @current_mood = mood
      end

      def display(message = nil)
        mood_data = MOODS[@current_mood]
        color_code = @colors[mood_data[:color]]
        reset = @colors[:reset]

        line = "#{color_code}#{mood_data[:icon]}#{reset}"
        line += " #{message}" if message
        
        @output.print "#{line}\r"
        @output.flush
      end

      def clear
        @output.print "\r#{' ' * 80}\r"
        @output.flush
      end

      def pulse(mood, message, duration: 0.5)
        set(mood)
        display(message)
        sleep(duration)
        clear
      end

      private

      def load_colors
        {
          reset: "\e[0m",
          white: "\e[37m",
          cyan: "\e[36m",
          yellow: "\e[33m",
          green: "\e[32m",
          red: "\e[31m"
        }
      end
    end
  end
end
