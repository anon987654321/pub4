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

    def self.prompt
      tier = LLM.tier || :none
      budget = format("$%.2f", LLM.remaining)
      
      # Show ⚡ if any model in current tier has tripped circuit
      tripped = LLM::TIERS[tier]&.any? { |m| !LLM.healthy?(m) } rescue false
      indicator = tripped ? "⚡" : ""
      
      "master[#{tier}#{indicator}|#{budget}]$ "
    rescue
      "master$ "
    end

    def self.repl
      require "tty-reader" rescue nil

      reader = defined?(TTY::Reader) ? TTY::Reader.new : nil
      pipeline = new

      Boot.banner
      puts "Type 'help' for commands, 'exit' to quit\n\n"

      Autocomplete.setup_tty(reader) if reader && defined?(Autocomplete)

      loop do
        prompt_str = self.prompt

        begin
          line = if reader
            reader.read_line(prompt_str)
          else
            print prompt_str
            $stdin.gets
          end
        rescue Interrupt
          puts
          break
        end

        break if line.nil?
        next if line.strip.empty?

        # Handle commands
        if defined?(Commands)
          cmd_result = Commands.dispatch(line.strip, pipeline: pipeline)
          break if cmd_result == :exit
          next if cmd_result.nil?
          # cmd_result is a Result, print it
          if cmd_result.respond_to?(:ok?)
            if cmd_result.ok?
              output = cmd_result.value[:rendered] || cmd_result.value[:response]
              puts "\n#{output}\n\n" if output && !output.empty?
            else
              puts "\nError: #{cmd_result.failure}\n\n"
            end
          end
          next
        end

        # Direct pipeline call
        result = pipeline.call({ text: line.strip })

        if result.ok?
          output = result.value[:rendered] || result.value[:response]
          puts "\n#{output}\n\n" if output && !output.empty?
        else
          puts "\nError: #{result.failure}\n\n"
        end
      end

      puts "Goodbye!"
    end

    def self.pipe
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
