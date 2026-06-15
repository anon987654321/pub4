# frozen_string_literal: true

module Master
  class Result
    CATEGORIES = {
      validation: "input failed preconditions",
      axiom_violation: "constitutional rule broken",
      provider_error: "upstream model / network failure",
      llm_failure: "LLM returned unusable output",
      llm_call_failure: "LLM dispatch exception (network / SDK)",
      no_api_key: "no LLM API key configured in env",
      infrastructure: "system / disk / git error",
      handler_exception: "unexpected error during handler execution",
      timeout: "operation exceeded deadline",
      rate_limit: "tier rate limit exceeded",
      budget: "cost limit hit",
      policy: "blocked by policy / kernel rule",
      shutdown: "user quit / shutdown requested",
      abort: "operation aborted",
    }.freeze

    def self.ok(value) = Ok.new(value)

    def self.err(msg, category: :unknown, context: nil)
      raise ArgumentError, "unknown category: #{category}" unless category == :unknown || CATEGORIES.key?(category)

      Err.new(msg, category, error_context(msg, context, caller_locations(1, 1).first))
    end

    def self.error_context(msg, context, location)
      base = {
        file: location&.path,
        method: location&.base_label,
        attempted: msg.to_s,
      }
      return base unless context
      return base.merge(context) if context.respond_to?(:merge)

      base.merge(detail: context)
    end

    def self.wrap(val) = val.is_a?(Result) ? val : Ok.new(val)

    class Ok < Result
      attr_reader :value

      def initialize(value)
        @value = value
        freeze
      end

      def ok? = true
      def err? = false
      def value! = @value
      def unwrap = @value
      def value_or(_) = @value

      def map(&blk) = Result.ok(blk.call(@value))
      def flat_map(&blk) = blk.call(@value)

      def and_then(label = nil, &blk)
        result = blk.call(@value)
        result.is_a?(Result) ? result : Result.ok(result)
      rescue StandardError => e
        Result.err("#{label || "stage"}: #{e.message}", category: :infrastructure)
      end

      def deconstruct_keys(_keys) = { value: @value }
      def to_s = @value.to_s
      def inspect = "Ok(#{@value.inspect})"
    end

    class Err < Result
      attr_reader :message, :category, :context

      RETRIABLE = %i[infrastructure timeout].freeze
      PERMANENT = %i[validation axiom_violation budget].freeze

      def initialize(message, category = :unknown, context = nil)
        raise ArgumentError, "message cannot be nil" if message.nil?
        raise ArgumentError, "category must be a symbol" unless category.is_a?(Symbol)

        @message = message
        @category = category
        @context = context
        freeze
      end

      def ok? = false
      def err? = true
      def value! = raise(Master::UnwrapError, "Err#value! called: #{@message}")
      def unwrap = value!
      def value_or(default) = default

      def map(&) = self
      def flat_map(&) = self
      def and_then(*) = self

      def retriable? = RETRIABLE.include?(@category)
      def permanent? = PERMANENT.include?(@category)

      def deconstruct_keys(_keys) = { message: @message, category: @category, context: @context }
      def to_s = @message
      def inspect = @context ? "Err(#{@category}: #{@message} @ #{@context})" : "Err(#{@category}: #{@message})"
    end
  end
end
