# frozen_string_literal: true

require "tty-screen"

module MASTER
  module UI
    module Help
      extend self

      COMMANDS = MASTER::CommandRegistry.help_commands.freeze
      ALIASES  = MASTER::CommandRegistry::COMMANDS.transform_values { |v| v[:aliases] || [] }.freeze
      EXAMPLES = MASTER::CommandRegistry::EXAMPLES

      def pastel = MASTER::UI.pastel

      TIPS = [
        "Tab for autocomplete",
        "Ctrl+C to cancel, twice to quit",
        "!! repeats last command",
        "%help for meta-ops (bypass LLM)",
        "command? shows help for that command",
        "Just type naturally — NLU routes to the right command",
        "<< opens multi-line input mode",
        "scan --hunt for deep bug analysis",
        "health --deep for full diagnostics",
        "forget undoes the last exchange",
        "session save <name> to bookmark progress",
        "model <name> switches LLM on the fly",
        "self runs full codebase analysis + auto-fix",
        "recent shows your last 10 commands",
        "help <keyword> to search commands",
      ].freeze

      GROUPS = {
        query: "Queries",
        analysis: "Analysis",
        session: "Session",
        system: "System",
        util: "Utility",
      }.freeze

      def show(command = nil)
        command = command.to_s.strip if command

        # "scan?" → show help for "scan"
        if command&.end_with?("?")
          command = command.chomp("?")
        end

        if command.nil? || command.empty?
          show_all
        elsif command == "tips"
          show_tips
        elsif command == "beginner"
          show_beginner
        elsif COMMANDS[command.to_sym]
          show_command(command.to_sym)
        else
          search_help(command)
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
          return if entries.empty?

          puts
          puts pastel.dim("  #{'─' * (width - 4)}")
          puts "  #{pastel.bold(GROUPS[group_key])}"
          entries.sort_by { |cmd, _| cmd.to_s }.each do |cmd, info|
            head = "  #{cmd.to_s.ljust(name_col)}"
            body_width = [width - head.length - 1, 24].max
            desc = info[:desc]
            als = ALIASES[cmd]
            desc = "#{desc} (#{als.join(', ')})" if als&.any?
            lines = wrap_text(desc, body_width)
            puts "#{head}#{lines.first}"
            lines.drop(1).each { |line| puts "#{' ' * head.length}#{line}" }
          end
          puts
        end

        puts pastel.dim("  #{MASTER::UI::ICONS[:detail]} #{tip}")
        puts
      end

      def show_tips
        puts
        TIPS.each { |t| puts "  #{MASTER::UI::ICONS[:bullet]} #{t}" }
        puts
      end

      def show_command(cmd)
        info = COMMANDS[cmd]
        return puts "Unknown command: #{cmd}" unless info

        width = safe_screen_width
        puts
        puts cmd.to_s.upcase
        wrap_text(info[:desc], width - 2).each { |line| puts "  #{line}" }
        als = ALIASES[cmd]
        puts "  aliases: #{als.join(', ')}" if als&.any?
        puts
        puts "  usage    #{info[:usage]}"
        ex = EXAMPLES[cmd]
        puts "  example  #{ex}" if ex
        puts
      end

      def search_help(keyword)
        low = keyword.downcase
        matches = COMMANDS.select do |cmd, info|
          cmd.to_s.include?(low) || info[:desc].downcase.include?(low)
        end

        if matches.empty?
          puts "  No commands matching '#{keyword}'."
          puts "  Try: help tips"
        else
          puts
          puts "Commands matching '#{keyword}':"
          matches.each do |cmd, info|
            puts "  #{cmd.to_s.ljust(20)} #{info[:desc]}"
          end
          puts
        end
      end

      def show_beginner
        puts
        puts "MASTER QUICK START"
        puts
        puts "  1. Just type naturally — MASTER understands plain English"
        puts "  2. For code analysis:  scan .          (scan current directory)"
        puts "  3. For refactoring:    refactor <file> (6-phase analysis)"
        puts "  4. For diagnostics:    health          (check system status)"
        puts "  5. For self-repair:    self            (analyze + fix everything)"
        puts
        puts "  #{pastel.dim('Prefix with % for instant commands: %help, %exit, %model')}"
        puts "  #{pastel.dim('Append ? to any command for help: scan? refactor?')}"
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
            lines[-1] = word
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
