


require_relative "commands/session_commands"
require_relative "commands/model_commands"
require_relative "commands/budget_commands"
require_relative "commands/code_commands"
require_relative "commands/misc_commands"
require_relative "commands/refactor_helpers"
require_relative "commands/workflow_commands"

module MASTER

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


    def repligen_command(cmd, args)

      
      case cmd
      when "repligen", "generate-image"
        return puts "Usage: repligen <prompt>" if args.nil? || args.empty?
        puts "🎨 Generating image: #{args}"
        result = Replicate.generate_image(prompt: args)
        if result.ok?
          puts "✓ Image generated: #{result.value[:urls]&.first || 'Success'}"
        else
          puts "✗ Error: #{result.error}"
        end
      when "generate-video"
        return puts "Usage: generate-video <prompt>" if args.nil? || args.empty?
        puts "🎬 Generating video: #{args}"
        result = Replicate.generate_video(prompt: args)
        if result.ok?
          puts "✓ Video generated: #{result.value[:urls]&.first || 'Success'}"
        else
          puts "✗ Error: #{result.error}"
        end
      end
    rescue => e
      $stderr.puts "Replicate error: #{e.message}"
      puts "✗ Failed: #{e.message}"
    end


    def postpro_command(cmd, args)

      
      case cmd
      when "postpro"
        if args.nil? || args.empty?
          puts "Postpro Operations:"
          Postpro.operations.each do |op|
            puts "  #{op[:id]} - #{op[:name]}"
          end
          return
        end

        parts = args.split(/\s+/, 2)
        operation = parts[0]
        image_url = parts[1]
        return puts "Usage: postpro <operation> <image_url>" if image_url.nil?
        
        puts "🔧 Enhancing with #{operation}..."
        result = Postpro.enhance(image_url: image_url, operation: operation)
        if result.ok?
          puts "✓ Enhanced: #{result.value[:urls]&.first || 'Success'}"
        else
          puts "✗ Error: #{result.error}"
        end
      when "enhance", "upscale"
        return puts "Usage: #{cmd} <image_url>" if args.nil? || args.empty?
        puts "🔧 #{cmd.capitalize}ing image..."
        result = cmd == "upscale" ? 
          Postpro.upscale(image_url: args) : 
          Postpro.enhance(image_url: args, operation: :upscale)
        if result.ok?
          puts "✓ Done: #{result.value[:urls]&.first || 'Success'}"
        else
          puts "✗ Error: #{result.error}"
        end
      end
    rescue => e
      $stderr.puts "Postpro error: #{e.message}"
      puts "✗ Failed: #{e.message}"
    end


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

      if input.strip == "!!"
        return Result.err("No previous command") unless @last_command
        input = @last_command
      elsif (shortcut = SHORTCUTS[input.strip])
        input = shortcut.is_a?(Symbol) ? @last_command : shortcut
      end


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
      when "shell"

        InteractiveShell.new.run
        nil
      when "exit", "quit"
        :exit
      else
        pipeline.call({ text: input })
      end
    end
  end


  module Autocomplete
    extend self

    COMMANDS = %w[help status budget clear history refactor chamber evolve speak exit quit ask scan].freeze

    def complete(partial, context: nil)
      completions = []


      if partial.match?(/^\w*$/)
        completions += COMMANDS.select { |c| c.start_with?(partial) }
      end


      if partial.include?('/') || partial.include?('\\') || partial.end_with?('.rb')
        completions += complete_path(partial)
      end


      if context
        case context
        when 'refactor', 'chamber'
          completions += complete_path(partial).select { |p| p.end_with?('.rb') }
        when 'speak', 'say'

        end
      end

      completions.uniq
    end

    def complete_path(partial)
      dir = File.dirname(partial)
      dir = '.' if dir == partial
      base = File.basename(partial)

      return [] unless Dir.exist?(dir)

      Dir.entries(dir)
         .reject { |e| e.start_with?('.') }
         .select { |e| e.start_with?(base) }
         .map { |e| File.join(dir, e) }
    rescue StandardError
      []
    end

    def setup_readline
      return unless defined?(Readline)

      Readline.completion_proc = proc do |input|
        complete(input)
      end
      Readline.completion_append_character = ' '
    end

    def setup_tty(reader)
      return unless reader.respond_to?(:on)

      reader.on(:keypress) do |event|
        if event.key.name == :tab
          word = event.line.text.split.last || ''
          matches = complete(word)
          if matches.size == 1

            event.line.replace(event.line.text.sub(/#{Regexp.escape(word)}$/, matches.first))
          elsif matches.size > 1
            puts "\n#{matches.join('  ')}"
          end
        end
      end
    end
  end


  module ProblemSolver
    extend self

    HOSTILE = [
      "What if the bug is in a different file?",
      "What if your fix creates a worse bug?",
      "What if the 'bug' is correct behavior?",
      "What if 5 other places have this bug?",
      "What if it worked yesterday—what changed?",
      "What if the error message lies?",
      "What if it's data, not code?",
      "What if it only works on your machine?",
      "What if you're fixing symptoms, not cause?",
      "What if deleting the feature is simpler?"
    ].freeze

    FIXES = {
      surgical:   { effort: 1, desc: "Minimal change to exact broken line" },
      defensive:  { effort: 2, desc: "Add guards, nil checks, validations" },
      refactor:   { effort: 3, desc: "Restructure to eliminate bug class" },
      workaround: { effort: 2, desc: "Route around it, don't touch it" },
      rewrite:    { effort: 4, desc: "Rewrite function from scratch" }
    }.freeze

    PROMPT = <<~P.freeze
      You are a senior debugger. Analyze this bug systematically.

      ERROR: {{ERROR}}
      CODE: {{CODE}}

      Provide:
      ROOT: [Why this happens - root cause, not symptoms]
      DOUBT: [Challenge your diagnosis - what could be wrong?]

      FIXES (safest to most invasive):
      1. SURGICAL: [Exact minimal change]
      2. DEFENSIVE: [Guards and validations]
      3. REFACTOR: [Structural fix]
      4. WORKAROUND: [Avoid the broken code]
      5. REWRITE: [Clean rewrite if needed]

      PICK: [Recommended fix and why]
      VERIFY: [How to confirm fix works]
      SIMILAR: [Other places with same bug pattern]
    P

    def analyze(error:, code:, llm: LLM)
      prompt = PROMPT.gsub("{{ERROR}}", error.to_s[0, 1000])
                     .gsub("{{CODE}}", code.to_s[0, 3000])

      result = llm.ask(prompt, tier: :fast)
      if result.ok?
        {
          analysis: result.value[:content],
          hostile_check: HOSTILE.sample,
          fixes: FIXES.keys
        }
      else
        { error: result.error }
      end
    rescue StandardError => e
      { error: e.message }
    end

    def hostile_check
      HOSTILE.sample
    end
  end


  module Keybindings
    BINDINGS = {
      ctrl_c:    { action: :interrupt,   desc: "Cancel current operation" },
      ctrl_d:    { action: :exit,        desc: "Exit MASTER" },
      ctrl_l:    { action: :clear,       desc: "Clear screen" },
      ctrl_r:    { action: :history,     desc: "Search history" },
      ctrl_z:    { action: :undo,        desc: "Undo last operation" },
      ctrl_y:    { action: :redo,        desc: "Redo undone operation" },
      tab:       { action: :autocomplete, desc: "Tab completion" },
      up:        { action: :history_up,  desc: "Previous command" },
      down:      { action: :history_down, desc: "Next command" },
      f1:        { action: :help,        desc: "Show help" },
      f2:        { action: :status,      desc: "Show status" }
    }.freeze

    extend self

    def setup(reader)
      return unless reader.respond_to?(:on)

      reader.on(:keyctrl_l) { print "\e[2J\e[H" }
      reader.on(:keyctrl_z) { Undo.undo if defined?(Undo) }
      reader.on(:keyctrl_y) { Undo.redo if defined?(Undo) }
    end

    def help_text
      lines = ["Keyboard Shortcuts:", ""]
      BINDINGS.each do |key, info|
        key_name = key.to_s.gsub('_', '+').gsub('ctrl', 'Ctrl')
        lines << "  #{key_name.ljust(12)} #{info[:desc]}"
      end
      lines.join("\n")
    end
  end
end
