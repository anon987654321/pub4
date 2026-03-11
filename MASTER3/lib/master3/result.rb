# frozen_string_literal: true

module Master3
  class Result
    def self.ok(value)    = Ok.new(value)
    def self.err(msg, category: :unknown) = Err.new(msg, category)

    class Ok
      attr_reader :value

      def initialize(value)
        @value = value
        freeze
      end

      def ok?   = true
      def err?  = false
      def value! = @value
      def unwrap = @value
      def value_or(_) = @value

      def map(&blk)      = Result.ok(blk.call(@value))
      def flat_map(&blk) = blk.call(@value)
      def and_then(label = nil, &blk)
        result = blk.call(@value)
        result.respond_to?(:ok?) ? result : Result.ok(result)
      rescue => e
        Result.err("#{label || "stage"}: #{e.message}", category: :unknown)
      end

      def deconstruct_keys(_keys) = { value: @value }
      def inspect = "Ok(#{@value.inspect})"
    end

    class Err
      attr_reader :message, :category

      RETRIABLE  = %i[infrastructure timeout].freeze
      PERMANENT  = %i[validation axiom_violation budget].freeze

      def initialize(message, category = :unknown)
        @message  = message
        @category = category
        freeze
      end

      def ok?    = false
      def err?   = true
      def value! = raise(RuntimeError, "Err#value! called: #{@message}")
      def unwrap = value!
      def value_or(default) = default

      def map(&)      = self
      def flat_map(&) = self
      def and_then(*) = self

      def retriable? = RETRIABLE.include?(@category)
      def permanent? = PERMANENT.include?(@category)

      def deconstruct_keys(_keys) = { message: @message, category: @category }
      def to_s = @message
      def inspect = "Err(#{@category}: #{@message})"
    end
  end
end
