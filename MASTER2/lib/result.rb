# frozen_string_literal: true

module MASTER
  # Functional Result monad (Ok/Err)
  class Result
    attr_reader :value, :error, :kind

    def initialize(value: nil, error: nil, kind: nil)
      @value = value
      @error = error
      @kind = kind || (error.nil? ? :ok : :err)
      freeze_state
    end

    def ok? = @kind == :ok
    def err? = @kind == :err
    def success? = ok?
    def failure = @error

    def value!
      raise(@error.to_s) if err?
      @value
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
      def ok(value) = new(value: value, kind: :ok)
      def err(error) = new(error: error, kind: :err)

      def try
        ok(yield)
      rescue StandardError => e
        err(e.message)
      end
    end

    private

    def freeze_state
      # Don't deep-freeze, just prevent reassignment
      @value.freeze if @value.is_a?(String)
      @error.freeze if @error.is_a?(String)
    end
  end

  # Shortcuts
  def self.Ok(v) = Result.ok(v)
  def self.Err(e) = Result.err(e)
end
