# frozen_string_literal: true

require_relative "result/ok_chaining"
require_relative "result/err_chaining"
require_relative "result/err_classification"

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

    def self.from(value, err_msg:, category: :validation, context: nil)
      value.nil? ? err(err_msg, category:, context:) : ok(value)
    end

    def self.from_observation(observation)
      observation.ok? ? ok(observation.detail) : err(observation.message, category: :unknown)
    end

    def self.err(msg, category: :unknown, context: nil)
      raise ArgumentError, "unknown category: #{category}" unless category == :unknown || CATEGORIES.key?(category)

      Err.new(msg, category, error_context(msg, context, caller_locations(1, 1).first))
    end

    def self.error_context(msg, context, location)
      base = { file: location&.path, method: location&.base_label, attempted: msg.to_s }
      return base unless context
      context.respond_to?(:merge) ? base.merge(context) : base.merge(detail: context)
    end

    def self.wrap(val) = val.is_a?(Result) ? val : Ok.new(val)

    class Ok < Result
      include OkChaining

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

      def deconstruct_keys(_keys) = { value: @value }
      def to_s = @value.to_s
      def inspect = "Ok(#{@value.inspect})"
    end

    class Err < Result
      include ErrChaining
      include ErrClassification

      attr_reader :message, :category, :context

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

      def deconstruct_keys(_keys) = { message: @message, category: @category, context: @context }
      def to_s = @message
      def inspect = @context ? "Err(#{@category}: #{@message} @ #{@context})" : "Err(#{@category}: #{@message})"
    end
  end
end
