# frozen_string_literal: true

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

    # RepLigen command handler
    def repligen_command(cmd, args)
      case cmd
      when "repligen", "generate-image"
        return puts "Usage: repligen <prompt>" if args.nil? || args.empty?
        result = RepligenBridge.generate_image(prompt: args)
        if result.ok?
          puts "+ image: #{result.value[:urls]&.first || result.value}"
        else
          $stderr.puts "- #{result.error}"
        end
      when "generate-video"
        return puts "Usage: generate-video <prompt>" if args.nil? || args.empty?
        result = RepligenBridge.generate_video(prompt: args)
        if result.ok?
          puts "+ video: #{result.value[:urls]&.first || result.value}"
        else
          $stderr.puts "- #{result.error}"
        end
      end
    rescue StandardError => e
      $stderr.puts "repligen: #{e.message}"
    end

    # PostPro command handler
    def postpro_command(cmd, args)
      case cmd
      when "postpro"
        if args.nil? || args.empty?
          puts "Operations:"
          PostproBridge.operations.each { |op| puts "  #{op[:id]} - #{op[:name]}" }
          puts "\nPresets:"
          puts PostproBridge.list_presets
          puts "\nStocks:"
          puts PostproBridge.list_stocks
          puts "\nLenses:"
          puts PostproBridge.list_lenses
          return
        end
        parts = args.split(/\s+/, 2)
        operation = parts[0]
        target = parts[1]

        # Check if it's a preset name
        if PostproBridge::PRESETS.key?(operation.to_sym) && target
          result = PostproBridge.apply_preset(target, preset: operation.to_sym)
          if result.ok?
            puts "+ #{operation}: #{result.value}"
          else
            $stderr.puts "- #{result.error}"
          end
        elsif target
          result = PostproBridge.enhance(image_url: target, operation: operation)
          if result.ok?
            puts "+ #{operation}: #{result.value[:urls]&.first || result.value}"
          else
            $stderr.puts "- #{result.error}"
          end
        else
          puts "Usage: postpro <operation|preset> <path|url>"
        end
      when "enhance", "upscale"
        return puts "Usage: #{cmd} <image_url>" if args.nil? || args.empty?
        result = cmd == "upscale" ?
          PostproBridge.upscale(image_url: args) :
          PostproBridge.enhance(image_url: args, operation: :upscale)
        if result.ok?
          puts "+ #{result.value[:urls]&.first || result.value}"
        else
          $stderr.puts "- #{result.error}"
        end
      end
    rescue StandardError => e
      $stderr.puts "postpro: #{e.message}"
    end

    # Fuzzy match for command suggestions (moved from Onboarding)
    def suggest_command(input)
      commands = Help::COMMANDS.keys.map(&:to_s)
      word = input.strip.split.first&.downcase
      return nil unless word

      commands.find { |c| Utils.levenshtein(word, c) <= 2 }
    end

    def show_did_you_mean(input)
      suggestion = suggest_command(input)
      return false unless suggestion

      puts UI.dim("  Did you mean: #{suggestion}?")
      true
    end

    # Shortcuts for power users
    SHORTCUTS = {
      "!!" => :repeat_last,
      "!r" => "autofix",
      "!c" => "chamber",
      "!e" => "evolve",
      "!s" => "status",
      "!b" => "budget",
      "!h" => "help",
    }.freeze

    HANDLED = Result.ok({ handled: true }).freeze

    def dispatch(input, pipeline:)
      # Handle shortcuts
      if input.strip == "!!"
        return Result.err("No previous command.") unless @last_command
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
        HANDLED
      when "hunt"
        hunt_bugs(args)
        HANDLED
      when "critique"
        critique_code(args)
        HANDLED
      when "conflict"
        detect_conflicts
        HANDLED
      when "learn"
        show_learnings(args)
        HANDLED
      when "status"
        Dashboard.new.render
        HANDLED
      when "budget"
        print_budget
        HANDLED
      when "clear"
        print "\e[2J\e[H"
        HANDLED
      when "history"
        print_cost_history
        HANDLED
      when "context"
        print_context_usage
        HANDLED
      when "session"
        manage_session(args)
        HANDLED
      when "sessions"
        print_saved_sessions
        HANDLED
      when "forget", "undo"
        undo_last_exchange
        HANDLED
      when "summary"
        print_session_summary
        HANDLED
      when "health"
        print_health
        HANDLED
      when "axioms-stats", "stats"
        print_axiom_stats
        HANDLED
      when "refactor", "autofix"
        autofix(args)
      when "chamber"
        chamber(args)
      when "evolve"
        evolve(args)
      when "opportunities", "opps"
        opportunities(args)
      when "axioms", "language-axioms"
        print_language_axioms(args)
        HANDLED
      when "self", "selftest", "self-test", "selfrun", "self-run"
        selftest_full(args)
      when "web", "server"
        start_web_server(args)
        HANDLED
      when "speak", "say"
        speak(args)
        HANDLED
      when "fix"
        fix_code(args)
        HANDLED
      when "browse"
        browse_url(args)
        HANDLED
      when "ideate", "brainstorm"
        ideate(args)
      when "model", "use"
        select_model(args)
        HANDLED
      when "models"
        list_models
        HANDLED
      when "pattern", "mode"
        select_pattern(args)
        HANDLED
      when "patterns", "modes"
        list_patterns
        HANDLED
      when "persona"
        manage_persona(args)
        HANDLED
      when "personas"
        list_personas
        HANDLED
      when "workflow"
        manage_workflow(args)
        HANDLED
      when "creative"
        creative_chamber(args)
        HANDLED
      when "scan"
        scan_code(args)
        HANDLED
      when "queue"
        manage_queue(args)
        HANDLED
      when "harvest"
        harvest_data(args)
        HANDLED
      when "capture", "session-capture"
        session_capture
        HANDLED
      when "review-captures"
        review_captures
        HANDLED
      when "repligen", "generate-image", "generate-video"
        repligen_command(cmd, args)
        HANDLED
      when "postpro", "enhance", "upscale"
        postpro_command(cmd, args)
        HANDLED
      when "cache"
        show_cache_stats(args)
        HANDLED
      when "multi-refactor", "mrefactor"
        multi_refactor(args)
      when "shell"
        InteractiveShell.new.run
        HANDLED
      when "exit", "quit"
        :exit
      else
        nil
      end
    end
  end
end
