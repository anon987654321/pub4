# frozen_string_literal: true

module MASTER
  # Help - Command documentation (NN/g compliant)
  module Help
    extend self

    COMMANDS = {
      help: { desc: "Show this help", usage: "help [command]" },
      ask: { desc: "Ask the LLM a question", usage: "ask <question>" },
      refactor: { desc: "Refactor a file", usage: "refactor <file>" },
      chamber: { desc: "Multi-model deliberation", usage: "chamber <file>" },
      evolve: { desc: "Self-improvement cycle", usage: "evolve [path]" },
      opportunities: { desc: "Analyze codebase for improvements", usage: "opportunities [path]" },
      session: { desc: "Session management", usage: "session [new|save|load|info]" },
      sessions: { desc: "List saved sessions", usage: "sessions" },
      forget: { desc: "Undo last exchange", usage: "forget" },
      summary: { desc: "Show conversation summary", usage: "summary" },
      status: { desc: "Show system status", usage: "status" },
      budget: { desc: "Show budget remaining", usage: "budget" },
      context: { desc: "Show context window usage", usage: "context" },
      history: { desc: "Show cost history", usage: "history" },
      health: { desc: "System health check", usage: "health" },
      speak: { desc: "Text-to-speech", usage: "speak <text>" },
      clear: { desc: "Clear screen", usage: "clear" },
      exit: { desc: "Exit MASTER", usage: "exit" },
    }.freeze

    TIPS = [
      "Use Tab for autocomplete",
      "Ctrl+C to cancel current operation",
      "Type 'help <command>' for details",
      "!! repeats last command, !r = refactor, !c = chamber",
      "Budget shown in prompt: master[tier|$X.XX]$",
      "⚡ in prompt means circuit tripped",
      "Sessions auto-save every 5 messages",
      "Use 'forget' to undo last exchange",
    ].freeze

    def show(command = nil)
      if command && COMMANDS[command.to_sym]
        show_command(command.to_sym)
      else
        show_all
      end
    end

    def show_all
      puts "\n  MASTER v#{VERSION} - Commands\n\n"

      COMMANDS.each do |cmd, info|
        puts "  #{cmd.to_s.ljust(14)} #{info[:desc]}"
      end

      puts "\n  Tips:"
      TIPS.first(4).each { |t| puts "    • #{t}" }
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
end
