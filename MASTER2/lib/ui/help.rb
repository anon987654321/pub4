# frozen_string_literal: true
require "tty-screen"

module MASTER
  module UI
    module Help
      extend self

      COMMANDS = {
        # Queries
        ask: { desc: "Ask the LLM a question", usage: "ask <question>", group: :query }.freeze,
        refactor: { desc: "Refactor a file with 6-phase analysis", usage: "refactor <file>", group: :query }.freeze,
        chamber: { desc: "Multi-model deliberation", usage: "chamber <file>", group: :query }.freeze,
        evolve: { desc: "Self-improvement cycle", usage: "evolve [path]", group: :query }.freeze,
        opportunities: { desc: "Find improvements", usage: "opportunities [path]", group: :query }.freeze,
        # Analysis
        hunt: { desc: "8-phase bug analysis", usage: "hunt <file>", group: :analysis }.freeze,
        critique: { desc: "Constitutional validation", usage: "critique <file>", group: :analysis }.freeze,
        learn: { desc: "Show matching learned patterns", usage: "learn <file>", group: :analysis }.freeze,
        conflict: { desc: "Detect principle conflicts", usage: "conflict", group: :analysis }.freeze,
        scan: { desc: "Scan for code smells", usage: "scan [path]", group: :analysis }.freeze,
        # Session
        session: { desc: "Session management", usage: "session [new|save|load]", group: :session }.freeze,
        sessions: { desc: "List saved sessions", usage: "sessions", group: :session }.freeze,
        forget: { desc: "Undo last exchange", usage: "forget", group: :session }.freeze,
        summary: { desc: "Conversation summary", usage: "summary", group: :session }.freeze,
        capture: { desc: "Capture session insights", usage: "capture", group: :session }.freeze,
        'review-captures': { desc: "Review captured insights", usage: "review-captures", group: :session }.freeze,
        # System
        status: { desc: "System status", usage: "status", group: :system }.freeze,
        budget: { desc: "Budget remaining", usage: "budget", group: :system }.freeze,
        context: { desc: "Context window usage", usage: "context", group: :system }.freeze,
        history: { desc: "Cost history", usage: "history", group: :system }.freeze,
        health: { desc: "Health check", usage: "health", group: :system }.freeze,
        'style-guides': { desc: "List/sync style guides", usage: "style-guides [sync]", group: :system }.freeze,
        # Utility
        help: { desc: "Show this help", usage: "help [command]", group: :util }.freeze,
        speak: { desc: "Text-to-speech", usage: "speak <text>", group: :util }.freeze,
        shell: { desc: "Interactive shell", usage: "shell", group: :util }.freeze,
        clear: { desc: "Clear screen", usage: "clear", group: :util }.freeze,
        exit: { desc: "Exit MASTER", usage: "exit", group: :util }.freeze,
      }.freeze

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
