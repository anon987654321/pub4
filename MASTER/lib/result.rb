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
      @value.freeze if @value && !@value.frozen?
      @error.freeze if @error && !@error.frozen?
      freeze
    end

    def ok? = @kind == :ok
    def err? = @kind == :err

    def unwrap = ok? ? @value : raise(@error.to_s)

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
