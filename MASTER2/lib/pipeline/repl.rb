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
        UI.warn("models0: OPENROUTER_API_KEY not set")
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
      puts "session0: #{name_or_id}"

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
            $stderr.print "\r(^C again to quit)\n"
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
            display_result(cmd_result, session) unless cmd_result.value.is_a?(Hash) && cmd_result.value[:handled]
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
          this_cost     = result.value[:cost].to_f
          running_total = session.total_cost + this_cost
          check_cost_limits(this_cost, running_total)
        end
        show_violations(result.value)
        session.add_assistant(output, model: result.value[:model], cost: result.value[:cost]) if output
      else
        # Print errors to stdout so they're always visible in the REPL
        puts "! #{result.failure}"
      end
    end

    def check_cost_limits(this_cost, session_total)
      @cost_limits ||= begin
        thresholds = YAML.safe_load_file(Paths.data_file("quality_thresholds.yml"))
        thresholds["cost_protection"] || {}
      rescue StandardError
        {}
      end
      max_request = @cost_limits["max_per_request"]&.to_f || 1.00
      max_session = @cost_limits["max_per_session"]&.to_f || 10.00
      # Warn only at hard limits — no noise below threshold
      if this_cost >= max_request
        $stderr.puts UI.dim("cost0: #{UI.currency_precise(this_cost)} > " \
                            "max_per_request #{UI.currency(max_request)}")
      end
      if session_total >= max_session
        $stderr.puts UI.dim("cost0: session #{UI.currency_precise(session_total)} > " \
                            "max_per_session #{UI.currency(max_session)}")
      end
    end

    def show_violations(value)
      axiom_violations    = value[:axiom_violations]
      zsh_violations      = value[:zsh_violations]
      council_vetoes      = value[:council_vetoes]
      security_veto       = value[:council_security_veto]
      # Compact one-liners to stderr — no noise when clean
      if security_veto
        veto_detail = council_vetoes&.any? ? " (#{council_vetoes.join(', ')})" : ""
        $stderr.puts UI.dim("council0: security veto#{veto_detail}")
      end
      if axiom_violations&.any?
        msg = "enforcer0: #{UI.pluralize(axiom_violations.size, 'violation')} — #{axiom_violations.join(', ')}"
        $stderr.puts UI.dim(msg)
      end
      if zsh_violations&.any?
        $stderr.puts UI.dim("lint0: #{UI.pluralize(zsh_violations.size, 'violation')} — " \
                            "#{zsh_violations.map { |v| v[:tool] }.join(', ')}")
      end
      beauty_score = value[:beauty_score]
      $stderr.puts UI.dim("✦ #{beauty_score}") if beauty_score&.> 0
    end

    # Build prompt using Pipeline.prompt with fallback
    def build_prompt(phase)
      Pipeline.prompt(phase: phase)
    rescue StandardError
      model_name = begin
        LLM.extract_model_name(LLM.prompt_model_name)
      rescue StandardError
        "?"
      end
      phase ? "master@#{model_name}$ " : "master@#{model_name}$ "
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
        nil  # history loss is non-critical
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
        nil  # non-critical
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
