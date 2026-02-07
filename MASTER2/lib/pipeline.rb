# frozen_string_literal: true

require "timeout"

module MASTER
  class Pipeline
    include Dry::Monads[:result]

    DEFAULT_STAGES = %i[compress guard debate ask lint admin render].freeze
    STAGE_TIMEOUT = 120 # seconds

    attr_reader :stages

    def initialize(stages: DEFAULT_STAGES)
      @stages = stages.map do |stage|
        # Support both stage names (symbols) and stage instances
        stage.respond_to?(:call) ? stage : stage_class(stage).new
      end
    end

    def call(input)
      @stages.reduce(Success(input)) do |result, stage|
        result.flat_map do |data|
          # Note: Timeout.timeout uses Thread#raise which may interrupt at any point.
          # This is acceptable for the current use case but could leave resources
          # in inconsistent states. Consider a safer timeout mechanism for production.
          Timeout.timeout(STAGE_TIMEOUT) { stage.call(data) }
        end
      end
    rescue Timeout::Error
      Failure("Pipeline timed out after #{STAGE_TIMEOUT}s")
    end

    # Convert stage name symbol to class
    # :input_tank -> Stages::InputTank
    def stage_class(name)
      class_name = name.to_s.split("_").map(&:capitalize).join
      Stages.const_get(class_name)
    end

    # Build dynamic prompt showing LLM tier and budget
    def self.prompt
      tier_level = LLM.tier
      tier_str = tier_level ? tier_level.to_s : "none"
      budget = format("$%.2f", LLM.remaining)
      
      # Check if any model in current tier has a tripped circuit
      tripped = if tier_level
        LLM::RATES.select { |_k, v| v[:tier] == tier_level }
                  .keys
                  .any? { |model| !LLM.healthy?(model) }
      else
        false
      end
      
      circuit_indicator = tripped ? "⚡" : ""
      
      "master[#{tier_str}#{circuit_indicator}|#{budget}]> "
    rescue => e
      # Fallback to basic prompt if DB isn't set up
      "master> "
    end

    # REPL mode with tty-prompt (graceful fallback)
    def self.repl
      begin
        require "tty-prompt"
      rescue LoadError
        # tty-prompt not available
      end

      begin
        require "tty-spinner"
      rescue LoadError
        # tty-spinner not available
      end

      prompt = defined?(TTY::Prompt) ? TTY::Prompt.new : nil
      spinner_class = defined?(TTY::Spinner) ? TTY::Spinner : nil

      Boot.banner
      puts "Type 'exit' or 'quit' to quit\n\n"

      loop do
        prompt_str = prompt
        
        if prompt
          input = prompt.ask("master$", required: false)
        else
          print "master$ "
          input = $stdin.gets&.chomp
        end

        break if input.nil? || input.strip.empty? || %w[exit quit].include?(input.strip.downcase)

        # Spinner blocks input while pipeline runs. Async input (type-ahead
        # while waiting) requires threaded pipeline execution — planned for v5.
        if spinner_class
          spinner = spinner_class.new("[:spinner] Processing...", format: :dots)
          spinner.auto_spin
        end

        result = new.call({ text: input })

        spinner&.success("Done!")

        if result.success?
          output = result.value![:rendered] || result.value![:response] || result.value!.inspect
          puts "\n#{output}\n\n"
        else
          puts "\nError: #{result.failure}\n\n"
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

      if result.success?
        puts JSON.generate(result.value!)
        exit 0
      else
        warn JSON.generate({ error: result.failure })
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
