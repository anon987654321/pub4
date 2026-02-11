# frozen_string_literal: true

# Load command modules
require_relative "commands/session_commands"
require_relative "commands/model_commands"
require_relative "commands/budget_commands"
require_relative "commands/code_commands"
require_relative "commands/misc_commands"
require_relative "commands/refactor_helpers"
require_relative "commands/workflow_commands"

module MASTER
  # Commands - REPL command dispatcher
  module Commands
    extend self
    include SessionCommands
    include ModelCommands
    include BudgetCommands
    include CodeCommands
    include MiscCommands
    include RefactorHelpers
    include WorkflowCommands

    @last_command = nil

    # Shortcuts for power users
    SHORTCUTS = {
      "!!" => :repeat_last,
      "!r" => "refactor",
      "!c" => "chamber",
      "!e" => "evolve",
      "!s" => "status",
      "!b" => "budget",
      "!h" => "help",
    }.freeze

    def dispatch(input, pipeline:)
      # Handle shortcuts
      if input.strip == "!!"
        return Result.err("No previous command") unless @last_command
        input = @last_command
      elsif (shortcut = SHORTCUTS[input.strip])
        input = shortcut.is_a?(Symbol) ? @last_command : shortcut
      end

      # Guard against nil after shortcut resolution
      return Result.err("No previous command to repeat.") if input.nil?

      @last_command = input unless input.to_s.start_with?("!")

      parts = input.strip.split(/\s+/, 2)
      cmd = parts[0]&.downcase
      args = parts[1]

      case cmd
      when "help", "?"
        Help.show(args)
        nil
      when "status"
        Dashboard.new.render
        nil
      when "budget"
        print_budget
        nil
      when "clear"
        print "\e[2J\e[H"
        nil
      when "history"
        print_cost_history
        nil
      when "context"
        print_context_usage
        nil
      when "session"
        manage_session(args)
        nil
      when "sessions"
        print_saved_sessions
        nil
      when "forget", "undo"
        undo_last_exchange
        nil
      when "summary"
        print_session_summary
        nil
      when "health"
        print_health
        nil
      when "axioms-stats", "stats"
        print_axiom_stats
        nil
      when "refactor"
        refactor(args)
      when "chamber"
        chamber(args)
      when "evolve"
        evolve(args)
      when "opportunities", "opps"
        opportunities(args)
      when "axioms", "language-axioms"
        print_language_axioms(args)
        nil
      when "selftest", "self-test", "selfrun", "self-run"
        SelfTest.run
      when "speak", "say"
        speak(args)
        nil
      when "fix"
        fix_code(args)
        nil
      when "browse"
        browse_url(args)
        nil
      when "ideate", "brainstorm"
        ideate(args)
      when "model", "use"
        select_model(args)
        nil
      when "models"
        list_models
        nil
      when "pattern", "mode"
        select_pattern(args)
        nil
      when "patterns", "modes"
        list_patterns
        nil
      when "persona"
        manage_persona(args)
        nil
      when "personas"
        list_personas
        nil
      when "workflow"
        manage_workflow(args)
        nil
      when "creative"
        creative_chamber(args)
        nil
      when "scan"
        scan_code(args)
        nil
      when "queue"
        manage_queue(args)
        nil
      when "harvest"
        harvest_data(args)
        nil
      when "capture", "session-capture"
        session_capture
        nil
      when "review-captures"
        review_captures
        nil
      when "shell"
        # Start interactive shell
        InteractiveShell.new.run
        nil
      when "exit", "quit"
        :exit
      else
        pipeline.call({ text: input })
      end
    end
  end
end
