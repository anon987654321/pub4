# frozen_string_literal: true

module MASTER
  class Pipeline
    DEFAULT_STAGES = %i[intake compress guard route council ask lint render].freeze
    MAX_INPUT_LENGTH = 100_000 # ~25k tokens

    @current_pattern = :auto
    @current_pattern_mutex = Mutex.new

    class << self
      def current_pattern
        @current_pattern_mutex.synchronize { @current_pattern }
      end

      def current_pattern=(value)
        @current_pattern_mutex.synchronize { @current_pattern = value }
      end
    end

    def initialize(stages: DEFAULT_STAGES, mode: :executor)
      @mode = mode
      @stages = stages.map do |stage|
        if stage.respond_to?(:call)
          stage
        else
          const_name = stage.to_s.capitalize.to_sym
          unless Stages.const_defined?(const_name)
            available = Stages.constants.join(", ")
            raise ArgumentError, "Unknown pipeline stage: #{stage}. Available: #{available}"
          end
          Stages.const_get(const_name).new
        end
      end
    end

    def call(input)
      text = input.is_a?(Hash) ? input[:text] : input.to_s

      raw = case @mode
            when :executor
              Executor.call(text, pattern: self.class.current_pattern)
            when :stages
              @stages.reduce(Result.ok(input)) do |result, stage|
                stage_name = stage.class.name&.split("::")&.last || stage.class.name
                result.and_then(stage_name) { |data| stage.call(data) }
              end
            when :direct
              LLM.ask(text, stream: true)
            else
              Executor.call(text, pattern: self.class.current_pattern)
            end

      normalize_result(raw)
    end

    private

    def normalize_result(result)
      return result if result.err?

      v = result.value
      return result unless v.is_a?(Hash)

      normalized = {
        response: v[:response] || v[:answer] || v[:content],
        rendered: v[:rendered],
        model: v[:model],
        cost: v[:cost],
        tokens_in: v[:tokens_in],
        tokens_out: v[:tokens_out],
        pattern: v[:pattern],
        steps: v[:steps],
        history: v[:history],
      }.compact

      if normalized[:response] && !normalized[:rendered]
        normalized[:rendered] = normalized[:response]
      end

      v.each do |key, val|
        normalized[key] = val unless normalized.key?(key)
      end

      Result.ok(normalized)
    end

    class << self
      def prompt
        model = LLM.prompt_model_name
        budget = LLM.budget_remaining
        tokens = Session.current.message_count rescue 0

        budget_str = budget < 10.0 ? " $#{format('%.2f', budget)}" : ""
        token_str = tokens > 0 ? " ↑#{format_tokens(tokens)}" : ""
        tripped = LLM.model_tiers[LLM.tier]&.any? { |m| !LLM.circuit_closed?(m) }
        indicator = tripped ? "!" : ""

        "master@#{model}#{indicator}#{token_str}#{budget_str}$ "
      rescue StandardError
        "master$ "
      end

      def format_tokens(n)
        return "#{n}" if n < 1000
        return "#{(n / 1000.0).round(1)}k" if n < 1_000_000
        "#{(n / 1_000_000.0).round(1)}M"
      end

      def repl
        begin
          require "tty-reader"
        rescue LoadError
        end

        reader = defined?(TTY::Reader) ? TTY::Reader.new : nil
        pipeline = new
        session = Session.current
        last_interrupt = nil  # Track Ctrl+C timing

        Boot.banner

        if ENV['MASTER_PRESCAN'] != 'false'
          Prescan.run(MASTER.root) if defined?(Prescan)
        end

        Onboarding.show_welcome if defined?(Onboarding)

        unless ENV["OPENROUTER_API_KEY"]
          UI.warn("OPENROUTER_API_KEY not set. Run: source ~/.zshrc")
        end

        puts "Session: #{UI.truncate_id(session.id)}"
        puts "Type 'help' for commands, Ctrl+C twice to quit"
        puts

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
          prompt_str = if defined?(WorkflowEngine) && session.metadata[:workflow]
                         phase = WorkflowEngine.current_phase(session)
                         "#{phase}> "
                       else
                         prompt
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
              puts "\nExiting..."
              session.save
              break
            else
              puts "\nPress Ctrl+C again to exit"
              last_interrupt = now
              next
            end
          end

          break if line.nil?

          unless line.valid_encoding?
            UI.warn("Invalid encoding in input — converting to UTF-8")
            line = line.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
          end

          if line.length > MAX_INPUT_LENGTH
            UI.warn("Input too long (#{line.length} chars). Truncated to #{MAX_INPUT_LENGTH}.")
            line = line[0, MAX_INPUT_LENGTH]
          end

          if line.strip.empty?
            Onboarding.suggest_on_empty if defined?(Onboarding)
            next
          end

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
              Onboarding.show_did_you_mean(line.strip) if defined?(Onboarding)
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

          session.save if session.message_count % 5 == 0
        end

        session.save
        
        if defined?(SessionCapture) && session.metadata_value(:successful)
          SessionCapture.auto_capture_if_successful
        end
        
        show_exit_summary(session)
      end

      def format_meta(value)
        parts = []
        parts << "#{value[:tokens_in]}→#{value[:tokens_out]}tok" if value[:tokens_in]
        parts << UI.currency_precise(value[:cost]) if value[:cost]
        parts << value[:model]&.split("/")&.last if value[:model]
        parts.join(" · ")
      end

      def show_exit_summary(session)
        cost = session.total_cost
        msgs = session.message_count
        puts
        puts UI.dim("  #{msgs} messages · #{UI.currency(cost)} · session #{UI.truncate_id(session.id)}")
        puts
      end

      def pipe
        require "json"
        input = JSON.parse($stdin.read, symbolize_names: true)
        result = new.call(input)

        if result.ok?
          puts JSON.generate(result.value)
          exit 0
        else
          warn JSON.generate({ error: result.failure })
          exit 1
        end
      rescue JSON::ParserError => e
        warn JSON.generate({ error: "Invalid JSON: #{e.message}" })
        exit 1
      end
    end
  end

  module Questions
    QUESTIONS_FILE = File.join(__dir__, "..", "data", "questions.yml")

    PHASES = %i[discover analyze ideate design implement validate deliver learn].freeze

    class << self
      def config
        @config ||= load_config
      end

      def load_config
        return {} unless File.exist?(QUESTIONS_FILE)
        YAML.safe_load_file(QUESTIONS_FILE) || {}
      end

      def for_phase(phase)
        phase_config = config[phase.to_s] || {}
        {
          purpose: phase_config["purpose"],
          questions: phase_config["questions"] || [],
          note: phase_config["note"],
        }
      end

      def ask_phase(phase)
        info = for_phase(phase)
        return if info[:questions].empty?

        puts
        puts UI.bold("#{phase.to_s.capitalize}: #{info[:purpose]}")
        info[:questions].each_with_index do |q, i|
          puts "  #{i + 1}. #{q}"
        end
        puts UI.dim("  Note: #{info[:note]}") if info[:note]
        puts
      end

      def guided_workflow(type = :new_feature)
        phases = phases_for_type(type)
        answers = {}

        phases.each do |phase|
          info = for_phase(phase)
          next if info[:questions].empty?

          puts UI.bold("\n#{phase.to_s.upcase}: #{info[:purpose]}")

          info[:questions].each do |question|
            print "  #{question} "
            answer = $stdin.gets&.strip
            answers[phase] ||= []
            answers[phase] << { question: question, answer: answer }
          end
        end

        answers
      end

      def phases_for_type(type)
        case type.to_sym
        when :bug_fix, :security_fix
          %i[analyze implement validate deliver]
        when :refactor
          %i[analyze design implement validate]
        else
          PHASES
        end
      end

      def prompt_for_phase(phase, context = "")
        info = for_phase(phase)
        return "" if info[:questions].empty?

        questions = info[:questions].map { |q| "- #{q}" }.join("\n")
        <<~PROMPT
          Phase: #{phase.to_s.upcase}
          Purpose: #{info[:purpose]}

          Consider these questions:

          Context: #{context}
        PROMPT
      end
    end
  end
end
