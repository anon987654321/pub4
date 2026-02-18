# frozen_string_literal: true
require "tty-screen"

module MASTER
  module UI
    module Help
      extend self

      COMMANDS = MASTER::CommandRegistry.help_commands.freeze

      TIPS = [
        "Tab for autocomplete",
        "Ctrl+C to cancel",
        "!! repeats last command",
      ].freeze

      GROUPS = {
        query: "Queries",
        analysis: "Analysis",
        session: "Session",
        system: "System",
        util: "Utility",
      }.freeze

      def show(command = nil)
        if command == "tips"
          show_tips
        elsif command && COMMANDS[command.to_sym]
          show_command(command.to_sym)
        else
          show_all
        end
      end

      def show_all
        width = safe_screen_width
        name_col = [COMMANDS.keys.map { |k| k.to_s.length }.max + 2, 22].max

        puts
        puts "MASTER HELP"
        puts "Type a command name, then press Enter."
        puts

        GROUPS.each_key do |group_key|
          entries = COMMANDS.select { |_cmd, info| info[:group] == group_key }
          next if entries.empty?

          puts GROUPS[group_key].upcase
          entries.sort_by { |cmd, _| cmd.to_s }.each do |cmd, info|
            head = "  #{cmd.to_s.ljust(name_col)}"
            body_width = [width - head.length - 1, 24].max
            lines = wrap_text(info[:desc], body_width)
            puts "#{head}#{lines.first}"
            lines.drop(1).each { |line| puts "#{" " * head.length}#{line}" }
          end
          puts
        end

        puts "TIP  #{tip}"
        puts
      end

      def show_tips
        puts
        TIPS.each { |t| puts "  . #{t}" }
        puts
      end

      def show_command(cmd)
        info = COMMANDS[cmd]
        return puts "Unknown command: #{cmd}" unless info

        width = safe_screen_width
        puts
        puts cmd.to_s.upcase
        wrap_text(info[:desc], width - 2).each { |line| puts "  #{line}" }
        puts
        puts "  usage  #{info[:usage]}"
        puts
      end

      def tip
        TIPS.sample
      end

      def autocomplete(partial)
        COMMANDS.keys.map(&:to_s).select { |c| c.start_with?(partial) }
      end

      private

      def safe_screen_width
        TTY::Screen.width
      rescue StandardError
        100
      end

      def wrap_text(text, width)
        return [""] if text.nil? || text.empty?

        words = text.split(/\s+/)
        lines = [""]
        words.each do |word|
          if lines.last.empty?
            lines.last = word
          elsif (lines.last.length + 1 + word.length) <= width
            lines.last << " #{word}"
          else
            lines << word
          end
        end
        lines
      end
    end

  end
end
