# frozen_string_literal: true

module MASTER
  class Pipeline
    DEFAULT_STAGES = %i[intake guard route debate ask lint render].freeze

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
        tier = LLM.tier || :none
        budget = UI.currency(LLM.budget_remaining)

        tripped = LLM::MODEL_TIERS[tier]&.any? { |m| !LLM.circuit_closed?(m) }
        indicator = tripped ? "⚡" : ""

        # Show context usage if session has messages
        ctx = ""
        if defined?(ContextWindow) && defined?(Session)
          u = ContextWindow.usage(Session.current)
          ctx = "|ctx:#{u[:percent].round}%" if u[:percent] > 5
        end

        "master[#{tier}#{indicator}|#{budget}#{ctx}]$ "
      rescue StandardError
        "master$ "
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

        puts "Session: #{UI.truncate_id(session.id)}"
        puts "Type 'help' for commands, 'exit' to quit\n\n"

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

            # Check for typos if command not recognized
            if cmd_result.respond_to?(:err?) && cmd_result.err?
              Onboarding.show_did_you_mean(line.strip) if defined?(Onboarding)
            end

            if cmd_result.respond_to?(:ok?)
              if cmd_result.ok?
                output = cmd_result.value[:rendered] || cmd_result.value[:response]
                if output && !output.empty?
                  puts "\n#{output}\n\n"
                  session.add_assistant(output, cost: cmd_result.value[:cost])
                end
              else
                puts "\nError: #{cmd_result.failure}\n\n"
              end
            end
            next
          end

          result = pipeline.call({ text: line.strip })

          if result.ok?
            output = result.value[:rendered] || result.value[:response]
            if output && !output.empty?
              puts "\n#{output}\n\n"
              session.add_assistant(
                output,
                model: result.value[:model],
                cost: result.value[:cost],
              )
            end
          else
            puts "\nError: #{result.failure}\n\n"
          end

          # Auto-save every 5 messages
          session.save if session.message_count % 5 == 0
        end

        session.save
        puts "Goodbye!"
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
