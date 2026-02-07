# frozen_string_literal: true

module MASTER
  class Pipeline
    DEFAULT_STAGES = %i[intake guard route ask render].freeze
    VALID_STAGES = %i[intake guard route ask render evolve execute].freeze

    def initialize(stages: DEFAULT_STAGES)
      # Validate stage names
      invalid_stages = stages.reject { |name| VALID_STAGES.include?(name) }
      unless invalid_stages.empty?
        raise ArgumentError, "Invalid stage(s): #{invalid_stages.join(', ')}. Valid stages: #{VALID_STAGES.join(', ')}"
      end
      
      @stage_names = stages
      @stages = stages.map { |name| Stages.const_get(name.to_s.capitalize).new }
    end

    def call(input)
      @stages.zip(@stage_names).reduce(Result.ok(input)) do |result, (stage, name)|
        result.flat_map do |data|
          stage_result = stage.call(data)
          # Add stage name context to errors
          if stage_result.err?
            Result.err("#{name}: #{stage_result.error}")
          else
            stage_result
          end
        end
      end
    end

    def repl
      $stdout.puts "MASTER v#{VERSION} — type 'exit' to quit"
      
      max_input_length = 50_000 # 50KB max input
      
      loop do
        $stdout.print "› "
        line = $stdin.gets
        break if line.nil? || line.strip.empty? || %w[exit quit].include?(line.strip)

        # Validate input length
        if line.bytesize > max_input_length
          $stderr.puts "error: Input too long (max #{max_input_length} bytes)"
          next
        end
        
        # Validate UTF-8
        unless line.valid_encoding?
          $stderr.puts "error: Invalid UTF-8 encoding"
          next
        end

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
