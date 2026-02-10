# frozen_string_literal: true

module MASTER
  # Pipeline - Uses Executor with hybrid patterns
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
              # Default: Use autonomous executor with pattern selection
              Executor.call(text, pattern: self.class.current_pattern)
            when :stages
              # Legacy: Stage-based pipeline
              @stages.reduce(Result.ok(input)) do |result, stage|
                stage_name = stage.class.name&.split("::")&.last || stage.class.name
                result.and_then(stage_name) { |data| stage.call(data) }
              end
            when :direct
              # Simple: Direct LLM call, no tools
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

      # Normalize known keys
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

      # Apply typography rendering if we have a response but no rendered version
      if normalized[:response] && !normalized[:rendered]
        normalized[:rendered] = normalized[:response]
      end

      # Preserve any custom keys from the original value
      v.each do |key, val|
        normalized[key] = val unless normalized.key?(key)
      end

      Result.ok(normalized)
    end

    class << self
      def prompt
        # Delegated to REPL for backward compatibility
        require_relative "repl"
        REPL.new(new).prompt
      end

      def format_tokens(n)
        # Delegated to REPL for backward compatibility
        require_relative "repl"
        REPL.new(new).format_tokens(n)
      end

      def repl
        require_relative "repl"
        REPL.new(new).run
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
