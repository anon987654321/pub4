# frozen_string_literal: true

require_relative "commands/session_commands"
require_relative "commands/model_commands"
require_relative "commands/budget_commands"
require_relative "commands/code_commands"
require_relative "commands/chat_commands"
require_relative "commands/misc_commands"
require_relative "commands/refactor_helpers"
require_relative "commands/workflow_commands"
require_relative "commands/system_commands"

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
          $stderr.puts "- #{result.error}"
        end
      when "generate-video"
        return puts "Usage: generate-video <prompt>" if args.nil? || args.empty?
        result = ReplicateBridge.generate_video(prompt: args)
        if result.ok?
          puts "+ video: #{result.value[:urls]&.first || result.value}"
        else
          $stderr.puts "- #{result.error}"
        end
      end
    rescue StandardError => e
      $stderr.puts "replicate: #{e.message}"
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
    rescue StandardError => e
      $stderr.puts "narrate: #{e.message}"
      Result.err(e.message)
    end

    def parse_segment_selection(args)
      return Result.ok(nil) unless args&.include?("--segments")

      parts = args.split("--segments", 2)
      return Result.ok(nil) if parts.size <= 1

      segment_ids = parts[1].strip.split(",").map { |s| s.strip.to_sym }
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
      commands = CommandRegistry.primary_commands
      word = input.strip.split.first&.downcase
      return nil unless word && word.length > 2

      commands.find { |c| Utils.levenshtein(word, c) <= 1 }
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
      "self" => [:selftest_full, false],
      "selftest" => [:selftest_full, false],
      "self-test" => [:selftest_full, false],
      "selfrun" => [:selftest_full, false],
      "self-run" => [:selftest_full, false],
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
        puts UI.dim("  [#{idx + 1}/#{requests.size}] #{request}")
        result = dispatch_one(request, pipeline: pipeline)
        results << { request: request, result: result }
        break if result == :exit
      end

      Result.ok({ handled: true, multi_intent: true, items: results.size, results: results })
    end

    def dispatch_one(input, pipeline:)
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
      when "doctor"
        doctor(args)
        HANDLED
      when "bootstrap"
        bootstrap(args)
        HANDLED
      when "history-dig"
        history_dig(args)
        HANDLED
      when "codify"
        codify(args)
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
      when "chat"
        enter_chat_mode(args)
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
      when "replicate", "repligen", "generate-image", "generate-video"
        replicate_command(cmd, args)
        HANDLED
      when "narrate", "narration"
        narrate_command(args)
        HANDLED
      when "postpro", "enhance", "upscale"
        postpro_command(cmd, args)
        HANDLED
      when "cache"
        show_cache_stats(args)
        HANDLED
      when "style-guides", "styleguides"
        style_guides(args)
        HANDLED
      when "multi-refactor", "mrefactor"
        multi_refactor(args)
      when "schedule"
        manage_schedule(args)
      when "heartbeat"
        manage_heartbeat(args)
      when "policy"
        manage_policy(args)
      when "shell"
        InteractiveShell.new.run
        HANDLED
      when "exit", "quit"
        :exit
      else
        nil
      end
    end

    # Wrapper methods for command table routing
    def show_help(args) = Help.show(args)
    def show_status(_args) = Dashboard.new.render
    def clear_screen(_args) = print("\e[2J\e[H")
    def handle_replicate(args) = replicate_command(@last_cmd || "replicate", args)
    def handle_postpro(args) = postpro_command(@last_cmd || "postpro", args)
    def start_shell(_args) = InteractiveShell.new.run
    def exit_repl(_args) = :exit

    private

    def split_requests(input)
      raw = input.to_s.strip
      return [] if raw.empty?

      chunks = raw
        .gsub("\r", "\n")
        .split(/\n+/)
        .flat_map { |line| line.split(/\s*;\s*/) }
        .map { |item| item.sub(/\A\s*(?:[-*]|\d+[.)])\s*/, "").strip }
        .reject(&:empty?)

      return chunks if chunks.size > 1

      qsplit = raw.split(/\?\s+/).map(&:strip).reject(&:empty?)
      if qsplit.size > 1
        return qsplit.map { |q| q.end_with?("?") ? q : "#{q}?" }
      end

      [raw]
    end

    def normalize_intent_input(input)
      text = input.to_s.strip
      lowered = text.downcase
      return text if lowered.empty?

      # Natural-language self-refactor requests
      if lowered.match?(/\b(self[\s-]?run|run .* through itself|refactor .* every|rewrite .* every|all files|entire repo|codebase)\b/)
        return "selfrun --strict --axioms --all-files" if lowered.match?(/\b(strict|axiom|every|all|entire|iterative|loop|diminishing)\b/)
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
