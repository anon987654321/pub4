# frozen_string_literal: true

module MASTER
  module Help
    extend self

    COMMANDS = {
      ask: { desc: "Ask the LLM a question", usage: "ask <question>", group: :query },
      refactor: { desc: "Refactor a file with 6-phase analysis", usage: "refactor <file>", group: :query },
      chamber: { desc: "Multi-model deliberation", usage: "chamber <file>", group: :query },
      evolve: { desc: "Self-improvement cycle", usage: "evolve [path]", group: :query },
      opportunities: { desc: "Find improvements", usage: "opportunities [path]", group: :query },
      hunt: { desc: "8-phase bug analysis", usage: "hunt <file>", group: :analysis },
      critique: { desc: "Constitutional validation", usage: "critique <file>", group: :analysis },
      learn: { desc: "Show matching learned patterns", usage: "learn <file>", group: :analysis },
      conflict: { desc: "Detect principle conflicts", usage: "conflict", group: :analysis },
      scan: { desc: "Scan for code smells", usage: "scan [path]", group: :analysis },
      session: { desc: "Session management", usage: "session [new|save|load]", group: :session },
      sessions: { desc: "List saved sessions", usage: "sessions", group: :session },
      forget: { desc: "Undo last exchange", usage: "forget", group: :session },
      summary: { desc: "Conversation summary", usage: "summary", group: :session },
      capture: { desc: "Capture session insights", usage: "capture", group: :session },
      'review-captures': { desc: "Review captured insights", usage: "review-captures", group: :session },
      status: { desc: "System status", usage: "status", group: :system },
      budget: { desc: "Budget remaining", usage: "budget", group: :system },
      context: { desc: "Context window usage", usage: "context", group: :system },
      history: { desc: "Cost history", usage: "history", group: :system },
      health: { desc: "Health check", usage: "health", group: :system },
      help: { desc: "Show this help", usage: "help [command]", group: :util },
      speak: { desc: "Text-to-speech", usage: "speak <text>", group: :util },
      shell: { desc: "Interactive shell", usage: "shell", group: :util },
      clear: { desc: "Clear screen", usage: "clear", group: :util },
      exit: { desc: "Exit MASTER", usage: "exit", group: :util },
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
      puts
      GROUPS.each do |group, label|
        cmds = COMMANDS.select { |_, v| v[:group] == group }
        puts "  #{label}"
        cmds.each do |cmd, info|
          puts "    #{cmd.to_s.ljust(12)} #{info[:desc]}"
        end
        puts
      end
    end

    def show_tips
      puts
      TIPS.each { |t| puts "  · #{t}" }
      puts
    end

    def show_command(cmd)
      info = COMMANDS[cmd]
      return puts "Unknown command: #{cmd}" unless info

      UI.header(cmd.to_s, width: cmd.to_s.length)
      puts "  #{info[:desc]}"
      puts "  Usage: #{info[:usage]}"
      puts
    end

    def tip
      TIPS.sample
    end

    def autocomplete(partial)
      COMMANDS.keys.map(&:to_s).select { |c| c.start_with?(partial) }
    end
  end

  module Onboarding
    extend self

    WELCOME = <<~MSG
      Welcome to MASTER v#{VERSION}

      Quick start:
        • Just type a question or request
        • Use 'help' for all commands
        • Use 'status' to see system state

      Examples:
        "Explain this Ruby code: def foo; end"
        "refactor lib/example.rb"
        "chamber lib/complex.rb"

    MSG

    EXAMPLES = [
      "Explain Ruby blocks vs procs",
      "How do I use OpenBSD pledge?",
      "Review this code for bugs",
      "help",
    ].freeze

    EMPTY_HINTS = [
      "Try: 'help' to see available commands",
      "Try: 'status' to see system state",
      "Try: 'budget' to check remaining funds",
      "Just type a question to ask the LLM",
    ].freeze

    class << self
      def first_run?
        !File.exist?(first_run_marker)
      end

      def show_welcome
        return unless first_run?

        puts
        puts UI.bold("MASTER v#{VERSION}")
        puts
        WELCOME.each_line { |l| puts "  #{l}" }
        mark_first_run
      end

      def suggest_on_empty
        hint = EMPTY_HINTS.sample
        puts UI.dim("  #{hint}")
      end

      def did_you_mean(input)
        commands = Help::COMMANDS.keys.map(&:to_s)
        word = input.strip.split.first&.downcase
        return nil unless word

        commands.find { |c| Utils.levenshtein(word, c) <= 2 }
      end

      def show_did_you_mean(input)
        suggestion = did_you_mean(input)
        return false unless suggestion

        puts UI.dim("  Did you mean: #{suggestion}?")
        true
      end

      private

      def first_run_marker
        File.join(Paths.var, ".first_run_complete")
      end

      def mark_first_run
        FileUtils.mkdir_p(File.dirname(first_run_marker))
        File.write(first_run_marker, Time.now.iso8601)
      end
    end
  end
end
