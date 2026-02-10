# frozen_string_literal: true

require "dry/monads"

module MASTER
  # Result monad backed by dry-monads
  # Preserves existing API: Result.ok(v), Result.err(e), .ok?, .err?, .value, .error
  class Result
    include Dry::Monads[:result]

    attr_reader :value, :error, :kind

    def initialize(value: nil, error: nil, kind: nil)
      @value = value
      @error = error
      @kind = kind || (error.nil? ? :ok : :err)
    end

    def ok? = @kind == :ok
    def err? = @kind == :err
    def success? = ok?
    def failure = @error

    def value!
      raise(@error.to_s) if err?
      @value
    end

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
      yield(@value)
    rescue StandardError => e
      Result.err(e.message)
    end

    def and_then(label = nil)
      return self if err?
      yield(@value)
    rescue StandardError => e
      Result.err("#{label ? "#{label}: " : ""}#{e.message}")
    end

    class << self
      def ok(value = nil) = new(value: value, kind: :ok)
      def err(error) = new(error: error, kind: :err)

      def try
        ok(yield)
      rescue StandardError => e
        err(e.message)
      end
    end
  end

  def self.Ok(v) = Result.ok(v)
  def self.Err(e) = Result.err(e)
end
