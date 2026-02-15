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

    # RepLigen command handler
    def repligen_command(cmd, args)
      require_relative "repligen_bridge"

      case cmd
      when "repligen", "generate-image"
        return puts "Usage: repligen <prompt>" if args.nil? || args.empty?
        puts "🎨 Generating image: #{args}"
        result = RepLigenBridge.generate_image(prompt: args)
        if result.ok?
          puts "✓ Image generated: #{result.value[:urls]&.first || 'Success'}"
        else
          puts "✗ Error: #{result.error}"
        end
      when "generate-video"
        return puts "Usage: generate-video <prompt>" if args.nil? || args.empty?
        puts "🎬 Generating video: #{args}"
        result = RepLigenBridge.generate_video(prompt: args)
        if result.ok?
          puts "✓ Video generated: #{result.value[:urls]&.first || 'Success'}"
        else
          puts "✗ Error: #{result.error}"
        end
      end
    rescue => e
      $stderr.puts "RepLigen error: #{e.message}"
      puts "✗ Failed: #{e.message}"
    end

    # PostPro command handler
    def postpro_command(cmd, args)
      require_relative "postpro_bridge"

      case cmd
      when "postpro"
        if args.nil? || args.empty?
          puts "PostPro Operations:"
          PostProBridge.operations.each do |op|
            puts "  #{op[:id]} - #{op[:name]}"
          end
          return
        end
        # Parse: postpro <operation> <image_url>
        parts = args.split(/\s+/, 2)
        operation = parts[0]
        image_url = parts[1]
        return puts "Usage: postpro <operation> <image_url>" if image_url.nil?

        puts "🔧 Enhancing with #{operation}..."
        result = PostProBridge.enhance(image_url: image_url, operation: operation)
        if result.ok?
          puts "✓ Enhanced: #{result.value[:urls]&.first || 'Success'}"
        else
          puts "✗ Error: #{result.error}"
        end
      when "enhance", "upscale"
        return puts "Usage: #{cmd} <image_url>" if args.nil? || args.empty?
        puts "🔧 #{cmd.capitalize}ing image..."
        result = cmd == "upscale" ?
          PostProBridge.upscale(image_url: args) :
          PostProBridge.enhance(image_url: args, operation: :upscale)
        if result.ok?
          puts "✓ Done: #{result.value[:urls]&.first || 'Success'}"
        else
          puts "✗ Error: #{result.error}"
        end
      end
    rescue => e
      $stderr.puts "PostPro error: #{e.message}"
      puts "✗ Failed: #{e.message}"
    end

    # Fuzzy match for command suggestions (moved from Onboarding)
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
      when "hunt"
        hunt_bugs(args)
        nil
      when "critique"
        critique_code(args)
        nil
      when "conflict"
        detect_conflicts
        nil
      when "learn"
        show_learnings(args)
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
      when "repligen", "generate-image", "generate-video"
        repligen_command(cmd, args)
        nil
      when "postpro", "enhance", "upscale"
        postpro_command(cmd, args)
        nil
      when "cache"
        show_cache_stats(args)
        nil
      when "multi-refactor", "mrefactor"
        multi_refactor(args)
      when "selfrun", "self-run"
        selfrun_full(args)
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
