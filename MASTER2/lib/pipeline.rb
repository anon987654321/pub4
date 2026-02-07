# frozen_string_literal: true

module MASTER
  class Pipeline
    DEFAULT_STAGES = %i[preprocessor adversarial_review postprocessor].freeze

    attr_reader :stages

    def initialize(stages: DEFAULT_STAGES)
      @stages = stages.map { |name| stage_class(name).new }
    end

    def call(input)
      @stages.reduce(Result.ok(input)) do |result, stage|
        result.flat_map { |data| stage.call(data) }
      end
    end

    def stage_class(name)
      class_name = name.to_s.split("_").map(&:capitalize).join
      Stages.const_get(class_name)
    end

    def self.repl
      begin
        require "tty-prompt"
      rescue LoadError
        nil
      end

      begin
        require "tty-spinner"
      rescue LoadError
        nil
      end

      prompt = defined?(TTY::Prompt) ? TTY::Prompt.new : nil
      spinner_class = defined?(TTY::Spinner) ? TTY::Spinner : nil

      puts "MASTER v#{MASTER::VERSION} REPL"
      puts "Type 'exit' or 'quit' to quit\n\n"

      loop do
        if prompt
          input = prompt.ask("master>", required: false)
        else
          print "master> "
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
  end
end
