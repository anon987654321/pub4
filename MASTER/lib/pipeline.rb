# frozen_string_literal: true

module MASTER
  class Pipeline
    DEFAULT_STAGES = %i[intake guard route ask render].freeze

    def initialize(stages: DEFAULT_STAGES)
      @stages = stages.map { |name| Stages.const_get(name.to_s.capitalize).new }
    end

    def call(input)
      @stages.reduce(Result.ok(input)) do |result, stage|
        result.flat_map { |data| stage.call(data) }
      end
    end

    def repl
      $stdout.puts "MASTER v#{VERSION} — type 'exit' to quit"
      loop do
        $stdout.print "› "
        line = $stdin.gets
        break if line.nil? || line.strip.empty? || %w[exit quit].include?(line.strip)

        result = call({ text: line.strip })
        if result.ok?
          $stdout.puts result.value[:rendered] || result.value[:response] || "(no response)"
        else
          $stderr.puts "error: #{result.error}"
        end
      end
    end
  end
end
