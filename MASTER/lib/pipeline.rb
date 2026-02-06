# frozen_string_literal: true

module MASTER
  class Pipeline
    attr_reader :stages

    def initialize(stages: [:intake, :guard, :route, :ask, :render])
      @stages = stages.map do |name|
        require_relative "stages/#{name}"
        stage_class = MASTER::Stages.const_get(name.to_s.split('_').map(&:capitalize).join)
        stage_class.new
      end
    end

    def call(input)
      @stages.reduce(Result.ok(input)) do |result, stage|
        result.flat_map { |data| stage.call(data) }
      end
    end

    def repl
      loop do
        $stdout.print "› "
        $stdout.flush
        line = $stdin.gets
        
        break if line.nil? || line.strip.empty? || %w[exit quit].include?(line.strip.downcase)
        
        result = call({ text: line.strip })
        
        if result.ok?
          $stdout.puts result.value[:rendered] || result.value[:response] || ""
        else
          $stderr.puts "Error: #{result.error}"
        end
      end
      
      $stdout.puts "\nGoodbye!"
    end
  end
end
