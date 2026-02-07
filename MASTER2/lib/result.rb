# frozen_string_literal: true

module MASTER
  # Functional Result monad (Ok/Err)
  class Result
    attr_reader :value, :error, :kind

    def initialize(value: nil, error: nil, kind: nil)
      @kind = kind || (error.nil? ? :ok : :err)
      @value = value
      @error = error
      # Freeze to prevent mutation after construction
      # Note: Hash/Array values are not frozen to allow mutation of result data structures
      # Only freeze simple immutable types (String, Symbol, Numeric, etc.)
      @value.freeze if @value.is_a?(String) || @value.is_a?(Symbol)
      @error.freeze unless @error.nil?
      freeze
    end

    def ok? = @kind == :ok
    def err? = @kind == :err
    def success? = ok?
    def failure = @error

    def value!
      ok? ? @value : raise(@error.to_s)
    end

    def unwrap = value!

    def value_or(default)
      ok? ? @value : default
    end

    def map
      return self if err?
      Result.ok(yield(@value))
    rescue StandardError => e
      Result.err(e.message)
    end

    def flat_map
      return self if err?
      result = yield(@value)
      result.is_a?(Result) ? result : Result.ok(result)
    rescue StandardError => e
      Result.err(e.message)
    end

    class << self
      def ok(value) = new(value: value, kind: :ok)
      def err(error) = new(error: error, kind: :err)

      def try
        ok(yield)
      rescue StandardError => e
        err(e.message)
      end
    end
  end

  # Shortcuts
  def self.Ok(v) = Result.ok(v)
  def self.Err(e) = Result.err(e)
end
