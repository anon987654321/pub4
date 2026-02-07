# frozen_string_literal: true

module MASTER
  # Functional Result monad (Ok/Err)
  class Result
    attr_reader :value, :error

    def initialize(value: nil, error: nil)
      @value = value
      @error = error
    end

    def ok? = @error.nil?
    def err? = !ok?

    def unwrap = ok? ? @value : raise(@error.to_s)

    def map
      return self if err?
      Result.ok(yield(@value))
    rescue => e
      Result.err(e.message)
    end

    def flat_map
      return self if err?
      yield(@value)
    rescue => e
      Result.err(e.message)
    end

    class << self
      def ok(value) = new(value: value)
      def err(error) = new(error: error)

      def try
        ok(yield)
      rescue => e
        err(e.message)
      end
    end
  end

  # Shortcuts - Uppercase Ok/Err convention intentionally matches Rust/Haskell style
  def self.Ok(v) = Result.ok(v)
  def self.Err(e) = Result.err(e)
end
