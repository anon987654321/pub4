# frozen_string_literal: true

module MASTER
  module PipelineRepl
    MAX_INPUT_LENGTH = 10_000
    MULTILINE_OPENER = "<<".freeze
    HISTORY_FILE = ".master_history".freeze
    MAX_HISTORY_LINES = 500

    def repl
      begin
        require "tty-reader"
      rescue LoadError
        # TTY not available
      end

      reader = defined?(TTY::Reader) ? TTY::Reader.new(history_cycle: true) : nil
      load_input_history(reader)
      pipeline = new
      session = Session.current
      last_interrupt = nil

      Boot.banner

      # Set initial model so prompt shows it immediately
      if LLM.configured?
        initial_model = LLM.send(:select_model) rescue nil
        LLM.current_model = LLM.extract_model_name(initial_model) if initial_model
      end

      # Prescan
      if ENV['MASTER_PRESCAN'] != 'false'
        Prescan.run(MASTER.root) if defined?(Prescan)
      end

      unless ENV["OPENROUTER_API_KEY"]
        UI.warn("OPENROUTER_API_KEY not set")
      end

      # Initialize workflow
      phase = nil
      if defined?(WorkflowEngine)
        workflow_result = WorkflowEngine.start_workflow(session)
        phase = WorkflowEngine.current_phase(session) if workflow_result.ok?
      end

      # Session name
      session_label = session.metadata_value(:name) || UI.truncate_id(session.id)
      puts "session #{session_label}"

      Autocomplete.setup_tty(reader) if reader && defined?(Autocomplete)

      loop do
        prompt_str = build_prompt(phase)

        begin
          line = read_input(reader, prompt_str)
          last_interrupt = nil
        rescue Interrupt
          now = Time.now
          if last_interrupt && (now - last_interrupt) < 1.0
            puts
            session.save
            break
          else
            puts " (again to quit)"
            last_interrupt = now
            next
          end
        end

        break if line.nil?

        # Validate encoding
        unless line.valid_encoding?
          UI.warn("Invalid encoding in input -- converting to UTF-8")
          line = line.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
        end

        # Multi-line input: << opens block, blank line ends it
        if line.strip == MULTILINE_OPENER
          line = read_multiline(reader)
          next if line.nil? || line.strip.empty?
        end

        # Validate length
        if line.length > MAX_INPUT_LENGTH
          UI.warn("Input too long (#{line.length} chars). Truncated to #{MAX_INPUT_LENGTH}.")
          line = line[0, MAX_INPUT_LENGTH]
        end

        next if line.strip.empty?

        # Save to history
        save_history_line(reader, line.strip)

        # Track user input in session
        session.add_user(line.strip)

        # Auto-name session from first user message
        if session.message_count == 1 && !session.metadata_value(:name)
          name = line.strip.split(/\s+/).first(5).join(" ")
          name = name[0, 40]
          session.write_metadata(:name, name)
        end

        if defined?(Commands)
          cmd_result = Commands.dispatch(line.strip, pipeline: pipeline)
          break if cmd_result == :exit

          if cmd_result.nil?
            # Unknown command — try did-you-mean before LLM fallthrough
            shown = Commands.show_did_you_mean(line.strip)
            next if shown
          elsif cmd_result.respond_to?(:ok?)
            unless cmd_result.value&.dig(:handled)
              display_result(cmd_result, session)
            end
            next
          end
        end

        result = pipeline.call({ text: line.strip })
        display_result(result, session)

        # Auto-save silently
        session.save if session.message_count % 5 == 0
      end

      save_input_history(reader)
      session.save

      # Auto-capture if session was marked successful
      if defined?(SessionCapture) && session.metadata_value(:successful)
        SessionCapture.auto_capture_if_successful
      end

      show_exit_summary(session)
    end

    private

    # Unified result display — eliminates duplicated rendering
    def display_result(result, session)
      if result.ok?
        output = result.value[:rendered] || result.value[:response]
        streamed = result.value[:streamed]
        if output && !output.empty? && !streamed
          puts
          puts output
        end
        if result.value[:cost]
          puts UI.dim("  #{format_meta(result.value)}")
        end
        session.add_assistant(
          output,
          model: result.value[:model],
          cost: result.value[:cost],
        ) if output
      else
        UI.error(result.failure)
      end
    end

    # Build prompt using Pipeline.prompt with fallback
    def build_prompt(phase)
      base = Pipeline.prompt
      phase ? "[#{phase}] #{base}" : base
    rescue StandardError
      model_name = LLM.extract_model_name(LLM.prompt_model_name) rescue "?"
      phase ? "#{phase} #{model_name}> " : "#{model_name}> "
    end

    # Read single or multi-line input
    def read_input(reader, prompt_str)
      if reader
        reader.read_line(prompt_str)
      else
        print prompt_str
        $stdin.gets
      end
    end

    # Read multi-line block until blank line
    def read_multiline(reader)
      lines = []
      loop do
        part = read_input(reader, "... ")
        break if part.nil? || part.strip.empty?
        lines << part.rstrip
      end
      lines.empty? ? nil : lines.join("\n")
    end

    # Load input history from file into TTY::Reader
    def load_input_history(reader)
      return unless reader
      path = history_path
      return unless File.exist?(path)

      File.readlines(path, chomp: true).last(MAX_HISTORY_LINES).each do |line|
        reader.add_to_history(line) rescue nil
      end
    rescue StandardError
      # History load failure is non-critical
    end

    # Save a single line to TTY::Reader history and our tracking array
    def save_history_line(reader, line)
      @history_lines ||= []
      @history_lines << line
      reader&.add_to_history(line) rescue nil
    end

    # Persist input history to file on exit
    def save_input_history(_reader)
      return if @history_lines.nil? || @history_lines.empty?

      path = history_path
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, @history_lines.last(MAX_HISTORY_LINES).join("\n") + "\n")
    rescue StandardError
      # History save failure is non-critical
    end

    def history_path
      File.join(MASTER.root, HISTORY_FILE)
    end
  end
end
