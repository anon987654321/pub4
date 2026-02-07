# frozen_string_literal: true

module MASTER
  class Pipeline
    DEFAULT_STAGES = %i[intake compress guard route council ask lint render].freeze

    def initialize(stages: DEFAULT_STAGES)
      @stages = stages.map do |stage|
        stage.respond_to?(:call) ? stage : Stages.const_get(stage.to_s.capitalize).new
      end
    end

    def call(input)
      @stages.reduce(Result.ok(input)) do |result, stage|
        result.flat_map { |data| stage.call(data) }
      end
    end

    class << self
      def prompt
        model = LLM.prompt_model_name
        budget = LLM.budget_remaining
        tokens = Session.current.token_count rescue 0

        # Shell-style: master@model [tokens] $cost$
        # Dense, informative prompt
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
          # TTY not available
        end

        reader = defined?(TTY::Reader) ? TTY::Reader.new : nil
        pipeline = new
        session = Session.current

        Boot.banner

        # First-run welcome
        Onboarding.show_welcome if defined?(Onboarding)

        # Check for API key
        unless ENV["OPENROUTER_API_KEY"]
          UI.warn("OPENROUTER_API_KEY not set. Run: source ~/.zshrc")
        end

        puts "Session: #{UI.truncate_id(session.id)}"
        puts "Type 'help' for commands, 'exit' to quit"
        puts

        Autocomplete.setup_tty(reader) if reader && defined?(Autocomplete)

        loop do
          prompt_str = prompt

          begin
            line = if reader
                     reader.read_line(prompt_str)
                   else
                     print prompt_str
                     $stdin.gets
                   end
          rescue Interrupt
            puts
            session.save
            break
          end

          break if line.nil?

          if line.strip.empty?
            Onboarding.suggest_on_empty if defined?(Onboarding)
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

          # Auto-save silently
          session.save if session.message_count % 5 == 0
        end

        session.save
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
end
