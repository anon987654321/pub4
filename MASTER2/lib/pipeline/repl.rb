# frozen_string_literal: true

module MASTER
  module PipelineRepl
    MAX_INPUT_LENGTH = 10_000
    MULTILINE_OPENER = "<<"
    HISTORY_FILE = ".master_history"
    MAX_HISTORY_LINES = 500

    def repl(web_port: nil)
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

      web_port ? Boot.banner_with_web(web_port) : Boot.banner

      # Set initial model so prompt shows it immediately
      if LLM.configured?
        initial_model = begin
          LLM.select_model
        rescue StandardError
          nil
        end
        LLM.current_model = LLM.extract_model_name(initial_model) if initial_model
      end

      # Prescan
      Prescan.run(MASTER.root) if (ENV["MASTER_PRESCAN"] != "false") && defined?(Prescan)

      unless ENV["OPENROUTER_API_KEY"]
        UI.warn("llm0: OPENROUTER_API_KEY not set")
        UI.info("   #{UI.icon(:arrow)} export OPENROUTER_API_KEY=sk-or-v1-...")
      end

      # Initialize workflow
      phase = nil
      if defined?(WorkflowEngine)
        workflow_result = WorkflowEngine.start_workflow(session)
        phase = WorkflowEngine.current_phase(session) if workflow_result.ok?
      end

      # Session name
      session_label = session.metadata_value(:name) || UI.truncate_id(session.id)
      name_or_id    = session.metadata_value(:name) ? session_label : "id=#{session_label}"
      puts "session0 at master0: #{name_or_id}"

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
            $stdout.print "\n (Ctrl+C again to quit)\n"
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
        if line.strip.start_with?(MULTILINE_OPENER)
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
            display_result(cmd_result, session) unless cmd_result.value&.dig(:handled)
            next
          end
        end

        # Gist #7: Elicitation checkpoint — pause before complex/ambiguous tasks
        pre_check = Stages::Intake.new.call({ text: line.strip })
        if pre_check.ok? && pre_check.value[:needs_elicitation]
          print "This looks complex — any constraints or preferences? (enter to skip) "
          clarification = $stdin.gets&.chomp
          line = "#{line.strip} [context: #{clarification}]" if clarification && !clarification.empty?
        end

        result = pipeline.call({ text: line.strip })
        display_result(result, session)

        # Auto-save silently
        session.save if session.message_count % 5 == 0
      end

      save_input_history(reader)
      session.save

      # Auto-capture if session was marked successful
      SessionCapture.auto_capture_if_successful if defined?(SessionCapture) && session.metadata_value(:successful)

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
          this_cost = result.value[:cost].to_f
          running_total = session.total_cost + this_cost
          total_str = running_total > 0 ? " [#{UI.currency_precise(running_total)} total]" : ""
          puts UI.dim("  #{format_meta(result.value)}#{total_str}")
          check_cost_limits(this_cost, running_total)
        end
        show_violations(result.value)
        if output
          session.add_assistant(
            output,
            model: result.value[:model],
            cost: result.value[:cost],
          )
        end
      else
        UI.error(result.failure)
      end
    end

    def check_cost_limits(this_cost, session_total)
      @cost_limits ||= begin
        f = File.join(MASTER.root, "data", "quality_thresholds.yml")
        YAML.safe_load_file(f)["cost_protection"] rescue {}
      end
      warn_at     = @cost_limits["warn_at"]&.to_f     || 0.50
      max_request = @cost_limits["max_per_request"]&.to_f  || 1.00
      max_session = @cost_limits["max_per_session"]&.to_f  || 10.00
      if this_cost >= max_request
        UI.warn("cost0: request #{UI.currency_precise(this_cost)} exceeds max_per_request #{UI.currency(max_request)}")
        UI.info("   #{UI.icon(:arrow)} set max_per_request in data/quality_thresholds.yml")
      elsif this_cost >= warn_at
        puts UI.dim("  cost0: approaching request limit (#{UI.currency_precise(this_cost)} / #{UI.currency(max_request)})")
      end
      if session_total >= max_session
        UI.warn("cost0: session #{UI.currency_precise(session_total)} exceeds max_per_session #{UI.currency(max_session)}")
      elsif session_total >= max_session * 0.8
        puts UI.dim("  cost0: session at #{UI.currency_precise(session_total)} / #{UI.currency(max_session)}")
      end
    end

    def show_violations(value)
      av = value[:axiom_violations]
      zv = value[:zsh_violations]
      cv = value[:council_vetoes]
      sv = value[:council_security_veto]
      if sv
        UI.warn("council0: security veto — review before deploying")
        UI.info("   #{UI.icon(:arrow)} vetoed by: #{cv&.join(', ')}") if cv&.any?
      elsif cv&.any?
        puts UI.dim("  council0: vetoed by #{cv.join(', ')}")
      end
      puts UI.dim("  enforcer0: #{UI.pluralize(av.size, 'axiom violation')} — #{av.join(', ')}") if av&.any?
      puts UI.dim("  zsh0: #{UI.pluralize(zv.size, 'violation')} — #{zv.map { |v| v[:tool] }.join(', ')}") if zv&.any?
    end

    # Build prompt using Pipeline.prompt with fallback
    def build_prompt(phase)
      base = Pipeline.prompt
      phase ? "[#{phase}] #{base}" : base
    rescue StandardError
      model_name = begin
        LLM.extract_model_name(LLM.prompt_model_name)
      rescue StandardError
        "?"
      end
      phase ? "#{phase} #{model_name} ❯ " : "#{model_name} ❯ "
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
        reader.add_to_history(line)
      rescue StandardError
        StandardError
      end
    rescue StandardError
      # History load failure is non-critical
    end

    # Save a single line to TTY::Reader history and our tracking array
    def save_history_line(reader, line)
      @history_lines ||= []
      @history_lines << line
      begin
        reader&.add_to_history(line)
      rescue StandardError
        StandardError
      end
    end

    # Persist input history to file on exit
    def save_input_history(_reader)
      return if @history_lines.nil? || @history_lines.empty?

      path = history_path
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "#{@history_lines.last(MAX_HISTORY_LINES).join("\n")}\n")
    rescue StandardError
      # History save failure is non-critical
    end

    def history_path
      File.join(MASTER.root, "var", HISTORY_FILE)
    end
  end
end
