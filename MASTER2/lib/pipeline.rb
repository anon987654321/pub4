# frozen_string_literal: true

module MASTER
  class Pipeline
    DEFAULT_STAGES = %i[input_tank council_debate refactor_engine output_tank].freeze

    attr_reader :stages

    def initialize(stages: DEFAULT_STAGES)
      @stages = stages.map { |name| stage_class(name).new }
    end

    def call(input)
      @stages.reduce(Result.ok(input)) do |result, stage|
        result.flat_map { |data| stage.call(data) }
      end
    end

    # Convert stage name symbol to class
    # :input_tank -> Stages::InputTank
    def stage_class(name)
      class_name = name.to_s.split('_').map(&:capitalize).join
      Stages.const_get(class_name)
    end

    # Build dynamic prompt showing LLM tier and budget
    def self.build_prompt
      tier = LLM.affordable_tier
      tier_str = tier ? tier.to_s : "none"
      budget = format("$%.2f", LLM.remaining)
      
      # Check if any model in current tier has a tripped circuit
      tripped = if tier
        LLM::RATES.select { |_k, v| v[:tier] == tier }
                  .keys
                  .any? { |model| !LLM.circuit_available?(model) }
      end
      
      circuit_indicator = tripped ? "⚡" : ""
      
      "master[#{tier_str}#{circuit_indicator}|#{budget}]> "
    rescue => e
      # Fallback to basic prompt if DB isn't set up
      "master> "
    end

    # REPL mode with tty-prompt (graceful fallback)
    def self.repl
      require "tty-prompt" rescue nil
      require "tty-spinner" rescue nil

      prompt = defined?(TTY::Prompt) ? TTY::Prompt.new : nil
      spinner_class = defined?(TTY::Spinner) ? TTY::Spinner : nil

      puts "MASTER v#{MASTER::VERSION} REPL"
      puts "Type 'exit' or 'quit' to quit\n\n"

      loop do
        prompt_str = build_prompt
        
        if prompt
          input = prompt.ask(prompt_str, required: false)
        else
          print prompt_str
          input = $stdin.gets&.chomp
        end

        break if input.nil? || input.strip.empty? || %w[exit quit].include?(input.strip.downcase)

        if spinner_class
          spinner = spinner_class.new("[:spinner] Processing...", format: :dots)
          spinner.auto_spin
        end

        result = new.call({ text: input })

        spinner&.success("Done!")

        if result.ok?
          output = result.value[:rendered] || result.value[:response] || result.value.inspect
          puts "\n#{output}\n\n"
        else
          puts "\nError: #{result.error}\n\n"
        end
      rescue Interrupt
        puts "\nInterrupted. Use 'exit' to quit."
      end

      puts "Goodbye!"
    end

    # Pipe mode: JSON stdin -> JSON stdout
    def self.pipe
      require "json"

      input = JSON.parse($stdin.read, symbolize_names: true)
      result = new.call(input)

      if result.ok?
        puts JSON.generate(result.value)
        exit 0
      else
        warn JSON.generate({ error: result.error })
        exit 1
      end
    rescue JSON::ParserError => e
      warn JSON.generate({ error: "Invalid JSON input: #{e.message}" })
      exit 1
    end
  end

  module Stages
    # Stages are loaded via require_relative in master.rb
  end
end
