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

    def inspect
      ok? ? "Ok(#{@value.inspect})" : "Err(#{@error.inspect})"
    end
    alias_method :to_s, :inspect

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

    def or
      return self if ok?
      yield
    end

    def tap_ok(&block)
      block.call(@value) if ok?
      self
    end

    def tap_err(&block)
      block.call(@error) if err?
      self
    end

    def to_h
      ok? ? { ok: true, value: @value } : { ok: false, error: @error }
    end

    def to_json(*args)
      require "json"
      to_h.to_json(*args)
    end

    def deconstruct_keys(keys)
      { ok: ok?, value: @value, error: @error }
    end

    class << self
      def ok(value) = new(value: value)
      
      def err(error)
        raise ArgumentError, "error cannot be nil" if error.nil?
        new(error: error)
      end

      def try
        ok(yield)
      rescue => e
        err(e.message)
      end

      def all(results)
        errors = results.select(&:err?).map(&:error)
        return err(errors) unless errors.empty?
        ok(results.map(&:value))
      end
    end
  end

  # Shortcuts
  def self.Ok(v) = Result.ok(v)
  def self.Err(e) = Result.err(e)
end
