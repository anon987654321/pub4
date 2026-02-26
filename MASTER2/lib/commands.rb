# frozen_string_literal: true

require "open3"
require "shellwords"
require_relative "commands/session_commands"
require_relative "commands/model_commands"
require_relative "commands/budget_commands"
require_relative "commands/code_commands"
require_relative "commands/chat_commands"
require_relative "commands/misc_commands"
require_relative "commands/refactor_helpers"
require_relative "commands/workflow_commands"
require_relative "commands/system_commands"
require_relative "commands/init_commands"

module MASTER
  # Commands - REPL command dispatcher
  module Commands
    extend self
    include SessionCommands
    include ModelCommands
    include BudgetCommands
    include CodeCommands
    include ChatCommands
    include MiscCommands
    include RefactorHelpers
    include WorkflowCommands
    include SystemCommands
    include InitCommands

    @last_command = nil

    # Replicate command handler (repligen kept as alias)
    def replicate_command(cmd, args)
      case cmd
      when "replicate", "repligen", "generate-image"
        return puts "Usage: replicate <prompt>" if args.nil? || args.empty?

        result = ReplicateBridge.generate_image(prompt: args)
        if result.ok?
          puts "+ image: #{result.value[:urls]&.first || result.value}"
        else
          warn "- #{result.error}"
        end
      when "generate-video"
        return puts "Usage: generate-video <prompt>" if args.nil? || args.empty?

        result = ReplicateBridge.generate_video(prompt: args)
        if result.ok?
          puts "+ video: #{result.value[:urls]&.first || result.value}"
        else
          warn "- #{result.error}"
        end
      end
    rescue StandardError => err
      warn "replicate: #{err.message}"
    end

    # Narrate command handler
    def narrate_command(args)
      return Result.err("REPLICATE_API_TOKEN not set") unless Replicate.available?
      return Result.err("narration module not loaded") unless defined?(MASTER::Replicate::Narration)

      selected_segments = parse_segment_selection(args)
      return selected_segments if selected_segments.err?

      result = MASTER::Replicate::Narration.generate_narration(segments: selected_segments.value)
      print_narration_results(result) if result.ok?
      result
    rescue StandardError => err
      warn "narrate: #{err.message}"
      Result.err(err.message)
    end

    def parse_segment_selection(args)
      return Result.ok(nil) unless args&.include?("--segments")

      parts = args.split("--segments", 2)
      return Result.ok(nil) if parts.size <= 1

      segment_ids = parts[1].strip.split(",").map { |seg_str| seg_str.strip.to_sym }
      all_segments = MASTER::Replicate::Narration::NARRATION_SEGMENTS
      selected = all_segments.select { |seg| segment_ids.include?(seg[:id]) }

      return Result.err("no matching segments") if selected.empty?

      Result.ok(selected)
    end

    def print_narration_results(result)
      result.value[:segments].each { |seg| puts "+ narrate: #{seg[:id]} completed" }
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
            warn "- #{result.error}"
          end
        elsif target
          result = PostproBridge.enhance(image_url: target, operation: operation)
          if result.ok?
            puts "+ #{operation}: #{result.value[:urls]&.first || result.value}"
          else
            warn "- #{result.error}"
          end
        else
          puts "Usage: postpro <operation|preset> <path|url>"
        end
      when "enhance", "upscale"
        return puts "Usage: #{cmd} <image_url>" if args.nil? || args.empty?

        result = if cmd == "upscale"
                   PostproBridge.upscale(image_url: args)
                 else
                   PostproBridge.enhance(image_url: args, operation: :upscale)
                 end
        if result.ok?
          puts "+ #{result.value[:urls]&.first || result.value}"
        else
          warn "- #{result.error}"
        end
      end
    rescue StandardError => err
      warn "postpro: #{err.message}"
    end

    # Fuzzy match for command suggestions (moved from Onboarding)
    def suggest_command(input)
      commands = CommandRegistry.primary_commands
      word = input.strip.split.first&.downcase
      return nil unless word && word.length > 2
      return nil if commands.include?(word)

      commands.find { |cmd| Utils.levenshtein(word, cmd) <= 1 }
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
      "go on" => :repeat_last,
      "continue" => :repeat_last,
      "continue?" => :repeat_last,
      "keep going" => :repeat_last,
      "proceed" => :repeat_last,
      "carry on" => :repeat_last,
    }.freeze

    # Command routing table: command => [method_name, returns_handled?]
    # If returns_handled is true, wraps result in HANDLED constant
    # If false, returns method result directly (may be Result, :exit, or nil)
    COMMAND_TABLE = {
      "help" => [:show_help, true],
      "?" => [:show_help, true],
      "hunt" => [:hunt_bugs, true],
      "critique" => [:critique_code, true],
      "conflict" => [:detect_conflicts, true],
      "learn" => [:show_learnings, true],
      "status" => [:show_status, true],
      "budget" => [:print_budget, true],
      "clear" => [:clear_screen, true],
      "history" => [:print_cost_history, true],
      "context" => [:print_context_usage, true],
      "session" => [:manage_session, true],
      "sessions" => [:print_saved_sessions, true],
      "forget" => [:undo_last_exchange, true],
      "undo" => [:undo_last_exchange, true],
      "summary" => [:print_session_summary, true],
      "health" => [:print_health, true],
      "doctor" => [:doctor, true],
      "bootstrap" => [:bootstrap, true],
      "history-dig" => [:history_dig, true],
      "codify" => [:codify, true],
      "axioms-stats" => [:print_axiom_stats, true],
      "stats" => [:print_axiom_stats, true],
      "refactor" => [:autofix, false],
      "autofix" => [:autofix, false],
      "chamber" => [:chamber, false],
      "evolve" => [:evolve, false],
      "opportunities" => [:opportunities, false],
      "opps" => [:opportunities, false],
      "axioms" => [:print_language_axioms, true],
      "language-axioms" => [:print_language_axioms, true],
      "self" => [:self_run, false],
      "selftest" => [:self_run, false],
      "self-test" => [:self_run, false],
      "selfrun" => [:self_run, false],
      "self-run" => [:self_run, false],
      "web" => [:start_web_server, true],
      "server" => [:start_web_server, true],
      "speak" => [:speak, true],
      "say" => [:speak, true],
      "fix" => [:fix_code, true],
      "browse" => [:browse_url, true],
      "chat" => [:enter_chat_mode, true],
      "ideate" => [:ideate, false],
      "brainstorm" => [:ideate, false],
      "model" => [:select_model, true],
      "use" => [:select_model, true],
      "models" => [:list_models, true],
      "pattern" => [:select_pattern, true],
      "mode" => [:select_pattern, true],
      "patterns" => [:list_patterns, true],
      "modes" => [:list_patterns, true],
      "persona" => [:manage_persona, true],
      "personas" => [:list_personas, true],
      "workflow" => [:manage_workflow, true],
      "creative" => [:creative_chamber, true],
      "scan" => [:scan_code, true],
      "queue" => [:manage_queue, true],
      "harvest" => [:harvest_data, true],
      "capture" => [:session_capture, true],
      "session-capture" => [:session_capture, true],
      "review-captures" => [:review_captures, true],
      "replicate" => [:handle_replicate, true],
      "repligen" => [:handle_replicate, true],
      "generate-image" => [:handle_replicate, true],
      "generate-video" => [:handle_replicate, true],
      "postpro" => [:handle_postpro, true],
      "enhance" => [:handle_postpro, true],
      "upscale" => [:handle_postpro, true],
      "cache" => [:show_cache_stats, true],
      "style-guides" => [:style_guides, true],
      "styleguides" => [:style_guides, true],
      "multi-refactor" => [:multi_refactor, false],
      "mrefactor" => [:multi_refactor, false],
      "shell" => [:start_shell, true],
      "exit" => [:exit_repl, false],
      "quit" => [:exit_repl, false],
    }.freeze

    HANDLED = Result.ok({ handled: true }).freeze

    def dispatch(input, pipeline:)
      return Result.err("No previous command to repeat.") if input.nil?

      # Split compound prompts into sequenced requests.
      requests = split_requests(input)
      return Result.err("Empty command.") if requests.empty?
      return dispatch_one(requests.first, pipeline: pipeline) if requests.size <= 1

      puts UI.dim("multi-intent: #{requests.size} items queued")
      results = []

      requests.each_with_index do |request, idx|
        puts UI.dim("  #{idx + 1}/#{requests.size} #{request}")
        result = dispatch_one(request, pipeline: pipeline)
        results << { request: request, result: result }
        break if result == :exit
      end

      Result.ok({ handled: true, multi_intent: true, items: results.size, results: results })
    end

    def dispatch_one(input, pipeline:)
      # Identity intercept -- Claude's RLHF overrides system prompt on this question
      if input.strip.downcase.match?(/\bwho are you\b|\bwhat are you\b|\byour name\b|\bintroduce yourself\b/)
        puts "\nMASTER v#{MASTER::VERSION} -- constitutional autonomous coding agent."
        return HANDLED
      end

      # Handle shortcuts
      if input.strip == "!!"
        return Result.err("No previous command.") unless @last_command

        input = @last_command
      elsif (shortcut = SHORTCUTS[input.strip])
        input = shortcut.is_a?(Symbol) ? @last_command : shortcut
      end

      return Result.err("No previous command to repeat.") if input.nil?

      input = normalize_intent_input(input)
      @last_command = input unless input.to_s.start_with?("!")

      parts = input.strip.split(/\s+/, 2)
      cmd = parts[0]&.downcase
      args = parts[1]

      # ! prefix -- run directly in shell, bypass LLM entirely
      if cmd&.start_with?("!")
        shell_cmd = "#{cmd[1..]} #{args}".strip
        output = Open3.capture2e(*Shellwords.split(shell_cmd)).first rescue `#{shell_cmd} 2>&1`
        print output
        puts unless output.end_with?("\n")
        return HANDLED
      end

      # Bare Unix commands -- run in shell without requiring ! prefix.
      # Prevents cat/ls/doas/git/etc from being sent to the LLM.
      if bare_shell_command?(cmd)
        # cd is a shell builtin -- must change Ruby process directory
        if cmd == "cd"
          target = args&.strip || Dir.home
          target = File.expand_path(target.empty? ? Dir.home : target, Dir.pwd)
          if Dir.exist?(target)
            Dir.chdir(target)
          else
            $stderr.puts "cd: #{target}: No such file or directory"
          end
          return HANDLED
        end
        output = `#{input.strip} 2>&1`
        print output
        puts unless output.end_with?("\n")
        return HANDLED
      end

      # Registry dispatch -- covers all known commands and aliases
      result = CommandRegistry.dispatch(cmd, args, pipeline: pipeline)
      return result.tap { |r| ReviewGate.run(r, input: input) if r.respond_to?(:ok?) } unless result.nil?

      # Unknown input -- fall through to LLM (nil return signals "not a command")
      nil
    end

    private

    def bare_shell_command?(cmd)
      return false unless cmd.is_a?(String)
      BARE_SHELL_COMMANDS.include?(cmd.downcase)
    end

    # Common Unix commands that should run directly without ! prefix.
    BARE_SHELL_COMMANDS = %w[
      ls ll la cat head tail grep rg find wc less more
      pwd cd mkdir rm mv cp touch chmod chown ln
      ps top htop kill pkill
      git svn
      ssh scp rsync curl wget
      doas sudo su
      uname hostname whoami id
      env printenv export
      echo printf
      ruby python python3 node npm gem bundle
      make rake cargo
      df du free
      tar gzip gunzip zip unzip
      date cal
    ].freeze

    def split_requests(input)
      raw = input.to_s.strip
      return [] if raw.empty?

      chunks = raw
        .gsub("\r", "\n")
        .split(/\n+/)
        .flat_map { |line| line.split(/\s*(?:&&|;)\s*/) }
        .map { |item| item.sub(/\A\s*(?:[-*]|\d+[.)])\s*/, "").strip }
        .reject(&:empty?)

      return chunks if chunks.size > 1

      # Comma-separated commands: "conflict, critique, hunt" -> three dispatches
      # Only split if each segment looks like a known command word (no spaces in first token)
      comma_chunks = raw.split(/,\s*/).map(&:strip).reject(&:empty?)
      if comma_chunks.size > 1 && comma_chunks.all? { |c| c.split.first&.match?(/\A[a-z][\w-]*\z/) }
        return comma_chunks
      end

      [raw]
    end

    def normalize_intent_input(input)
      text = input.to_s.strip
      lowered = text.downcase
      return text if lowered.empty?

      # Natural-language self-refactor requests
      if lowered.match?(/\b(self[\s-]?run|run .* through itself|refactor .* every|rewrite .* every|all files|entire repo|codebase)\b/)
        if lowered.match?(/\b(strict|axiom|every|all|entire|iterative|loop|diminishing)\b/)
          return "selfrun --strict --axioms --all-files"
        end

        return "selfrun"
      end

      # Natural-language lint/scan requests
      if lowered.match?(/\b(lint|validate|syntax check|scan)\b/) &&
         lowered.match?(/\b(html|erb|css|javascript|js|rust|yaml|yml|all files|repo)\b/)
        return "multi-refactor . --strict --axioms --all-files"
      end

      # Health/status phrasing
      return "health" if lowered.match?(/\b(health|diagnostic|doctor|check setup)\b/)
      return "status" if lowered.match?(/\b(status|where are we|summary)\b/)

      text
    end
  end
end
