# frozen_string_literal: true

module MASTER
  # Help - Command documentation (NN/g compliant)
  module Help
    extend self

    COMMANDS = {
      # Queries
      ask: { desc: "Ask the LLM a question", usage: "ask <question>", group: :query },
      refactor: { desc: "Refactor a file with 6-phase analysis", usage: "refactor <file>", group: :query },
      chamber: { desc: "Multi-model deliberation", usage: "chamber <file>", group: :query },
      evolve: { desc: "Self-improvement cycle", usage: "evolve [path]", group: :query },
      opportunities: { desc: "Find improvements", usage: "opportunities [path]", group: :query },
      # Analysis
      hunt: { desc: "8-phase bug analysis", usage: "hunt <file>", group: :analysis },
      critique: { desc: "Constitutional validation", usage: "critique <file>", group: :analysis },
      learn: { desc: "Show matching learned patterns", usage: "learn <file>", group: :analysis },
      conflict: { desc: "Detect principle conflicts", usage: "conflict", group: :analysis },
      scan: { desc: "Scan for code smells", usage: "scan [path]", group: :analysis },
      # Session
      session: { desc: "Session management", usage: "session [new|save|load]", group: :session },
      sessions: { desc: "List saved sessions", usage: "sessions", group: :session },
      forget: { desc: "Undo last exchange", usage: "forget", group: :session },
      summary: { desc: "Conversation summary", usage: "summary", group: :session },
      capture: { desc: "Capture session insights", usage: "capture", group: :session },
      'review-captures': { desc: "Review captured insights", usage: "review-captures", group: :session },
      # System
      status: { desc: "System status", usage: "status", group: :system },
      budget: { desc: "Budget remaining", usage: "budget", group: :system },
      context: { desc: "Context window usage", usage: "context", group: :system },
      history: { desc: "Cost history", usage: "history", group: :system },
      health: { desc: "Health check", usage: "health", group: :system },
      # Utility
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
end
