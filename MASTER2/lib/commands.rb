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
    # Common words that are NOT typos of commands — skip did-you-mean
    NATURAL_WORDS = %w[
      hello hey hi thanks thank you yes no ok okay sure create update
      delete remove change make build run start stop please what how
      why where when who which can could would should do does did
      the this that these those a an is are was were be been being
      deploy install setup configure fix help me my it its
      ask tell show explain describe
    ].to_set.freeze

    def suggest_command(input)
      commands = CommandRegistry.primary_commands
      word = input.strip.split.first&.downcase
      return nil unless word && word.length > 2
      return nil if commands.include?(word)
      return nil if NATURAL_WORDS.include?(word)

      # Only suggest for plausible typos: distance ≤ 2, shares first char,
      # and similar length.
      scored = commands.filter_map do |cmd|
        d = Utils.levenshtein(word, cmd)
        next unless d <= 2 && d < word.length
        next unless word[0] == cmd[0] || word[-1] == cmd[-1]
        next unless (word.length - cmd.length).abs <= 2

        [cmd, d]
      end.sort_by { |_, d| d }.first(3).map(&:first)

      scored.empty? ? nil : scored
    end

    def show_did_you_mean(input)
      suggestions = suggest_command(input)
      return false unless suggestions&.any?

      puts UI.dim("  Did you mean: #{suggestions.join(', ')}?")
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
      signals = defined?(NLU) ? NLU.classify_signals(input.strip) : Set.new
      if signals.include?(:identity_query)
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

      # Comma-separated commands: "conflict, critique, debug" -> three dispatches
      # Only split if each segment looks like a known command word (no spaces in first token)
      comma_chunks = raw.split(/,\s*/).map(&:strip).reject(&:empty?)
      if comma_chunks.size > 1 && comma_chunks.all? { |c| c.split.first&.match?(/\A[a-z][\w-]*\z/) }
        return comma_chunks
      end

      [raw]
    end

    def normalize_intent_input(input)
      text = input.to_s.strip
      return text if text.empty?

      signals = defined?(NLU) ? NLU.classify_signals(text) : Set.new
      low = text.downcase

      if signals.include?(:self_run_request)
        return "self-fix --dry-run" if low.match?(/\b(dry.?run|preview|what would)\b/)
        return "self-fix"
      end

      return "multi-refactor . --strict --axioms --all-files" if signals.include?(:lint_request)
      return "health" if signals.include?(:health_request)
      return "status" if signals.include?(:status_request)

      # "fix everything" / "autofix all" / "fix all issues"
      return "fix --all" if low.match?(/\b(fix|autofix|repair)\b.{0,20}\b(all|everything|entire|whole)\b/i) ||
                            low.match?(/\b(autofix|fix)\s+all\b/i)

      # "evolve using <model>" / "evolve with claude" -> model select + evolve
      if low.start_with?("evolve") && (m = low.match(/\busing\s+([\w.\-]+)\s*$/))
        model = m[1]
        return "model #{model}\nevolve"
      end

      # "scan everything" / "check all files" / "audit codebase"
      return "scan ." if low.match?(/\b(scan|check|audit|analyze|analyse)\b.{0,20}\b(all|everything|codebase|entire|whole)\b/i)

      # "commit" / "save changes" / "commit changes"
      return "shell git add -A && git commit -m 'manual commit'" if low.match?(/\A(commit|commit changes|save changes)\z/i)

      text
    end
  end
end
