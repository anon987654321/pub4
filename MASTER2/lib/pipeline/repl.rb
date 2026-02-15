# frozen_string_literal: true

module MASTER
  module PipelineRepl
    MAX_INPUT_LENGTH = 10_000

    def repl
      begin
        require "tty-reader"
      rescue LoadError
        # TTY not available
      end

      reader = defined?(TTY::Reader) ? TTY::Reader.new : nil
      pipeline = new
      session = Session.current
      last_interrupt = nil  # Track Ctrl+C timing

      Boot.banner

      # Set initial model so prompt shows it immediately
      if LLM.configured?
        initial_model = LLM.send(:select_model_for_tier, :premium) rescue nil
        if initial_model
          LLM.current_model = LLM.extract_model_name(initial_model)
          LLM.current_tier = :premium
        end
      end

      # Add prescan before starting work
      if ENV['MASTER_PRESCAN'] != 'false'
        Prescan.run(MASTER.root) if defined?(Prescan)
      end

      # Check for API key
      unless ENV["OPENROUTER_API_KEY"]
        UI.warn("OPENROUTER_API_KEY not set. Run: source ~/.zshrc")
      end

      puts "Session: #{UI.truncate_id(session.id)}"
      puts "Type 'help' for commands, Ctrl+C twice to quit"
      puts

      # Initialize workflow if not present
      if defined?(WorkflowEngine)
        workflow_result = WorkflowEngine.start_workflow(session)
        if workflow_result.ok?
          phase = WorkflowEngine.current_phase(session)
          phase_info = Questions.for_phase(phase) if defined?(Questions)

          puts UI.bold("Phase: #{phase.to_s.upcase}")
          puts UI.dim("  Purpose: #{phase_info[:purpose]}") if phase_info
          puts
        end
      end

      Autocomplete.setup_tty(reader) if reader && defined?(Autocomplete)

      loop do
        # Budget-aware ❯ prompt — green >$5, yellow >$1, red <$1
        budget = LLM.budget_remaining rescue 10.0
        prompt_color = if budget > 5.0 then :green
                       elsif budget > 1.0 then :yellow
                       else :red
                       end
        prompt_char = UI.pastel.bold.send(prompt_color, "❯")
        model_name = LLM.extract_model_name(LLM.prompt_model_name) rescue "?"
        model_tag = UI.pastel.bright_black(model_name)
        prompt_str = if defined?(WorkflowEngine) && session.metadata[:workflow]
                       phase = WorkflowEngine.current_phase(session)
                       "#{UI.pastel.cyan(phase.to_s)} #{model_tag} #{prompt_char} "
                     else
                       "#{model_tag} #{prompt_char} "
                     end

        begin
          line = if reader
                   reader.read_line(prompt_str)
                 else
                   print prompt_str
                   $stdin.gets
                 end
          last_interrupt = nil  # Reset on successful input
        rescue Interrupt
          now = Time.now
          if last_interrupt && (now - last_interrupt) < 1.0
            # Double Ctrl+C within 1 second - exit
            puts "\nExiting..."
            session.save
            break
          else
            # First Ctrl+C - warn user
            puts "\nPress Ctrl+C again to exit"
            last_interrupt = now
            next
          end
        end

        break if line.nil?

        # Validate encoding
        unless line.valid_encoding?
          UI.warn("Invalid encoding in input — converting to UTF-8")
          line = line.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
        end

        # Validate length
        if line.length > MAX_INPUT_LENGTH
          UI.warn("Input too long (#{line.length} chars). Truncated to #{MAX_INPUT_LENGTH}.")
          line = line[0, MAX_INPUT_LENGTH]
        end

        if line.strip.empty?
          next
        end

        # Track user input in session
        session.add_user(line.strip)

        if defined?(Commands)
          cmd_result = Commands.dispatch(line.strip, pipeline: pipeline)
          break if cmd_result == :exit
          next if cmd_result.nil?

          if cmd_result.respond_to?(:ok?)
            if cmd_result.ok?
              output = cmd_result.value[:rendered] || cmd_result.value[:response]
              if output && !output.empty?
                puts
                puts output
                puts UI.dim("  #{format_meta(cmd_result.value)}") if cmd_result.value[:cost]
                session.add_assistant(output, cost: cmd_result.value[:cost])
              end
            else
              puts
              UI.error(cmd_result.failure)
            end
          elsif cmd_result.respond_to?(:err?) && cmd_result.err?
            # Unknown command - suggest similar
            Commands.show_did_you_mean(line.strip) if defined?(Commands)
          end
          next
        end

        result = pipeline.call({ text: line.strip })

        if result.ok?
          output = result.value[:rendered] || result.value[:response]
          if output && !output.empty?
            puts
            puts output
            puts UI.dim("  #{format_meta(result.value)}") if result.value[:cost]
            session.add_assistant(
              output,
              model: result.value[:model],
              cost: result.value[:cost],
            )
          end
        else
          puts
          UI.error(result.failure)
        end

        # Auto-save silently
        session.save if session.message_count % 5 == 0
      end

      session.save

      # Auto-capture if session was marked successful
      if defined?(SessionCapture) && session.metadata_value(:successful)
        SessionCapture.auto_capture_if_successful
      end

      show_exit_summary(session)
    end
  end
end
