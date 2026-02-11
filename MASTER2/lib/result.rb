# frozen_string_literal: true

module MASTER
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
      def ok(value = nil) = new(value: value, kind: :ok)

      def err(error) = new(error: error, kind: :err)

      def try
        ok(yield)
      rescue StandardError => e
        err(e.message)
      end
    end

    private

    def freeze_state
      @value.freeze if @value.is_a?(Hash) || @value.is_a?(Array) || @value.is_a?(String)
      @error.freeze if @error.is_a?(String)
      freeze
    end
  end

  def self.Ok(v) = Result.ok(v)
  def self.Err(e) = Result.err(e)

  module Utils
    module_function

    def levenshtein(a, b)
      return b.length if a.empty?
      return a.length if b.empty?

      m = Array.new(a.length + 1) { Array.new(b.length + 1, 0) }
      (0..a.length).each { |i| m[i][0] = i }
      (0..b.length).each { |j| m[0][j] = j }

      (1..a.length).each do |i|
        (1..b.length).each do |j|
          cost = a[i - 1] == b[j - 1] ? 0 : 1
          m[i][j] = [m[i - 1][j] + 1, m[i][j - 1] + 1, m[i - 1][j - 1] + cost].min
        end
      end

      m[a.length][b.length]
    end

    def similarity(a, b)
      return 1.0 if a == b
      return 0.0 if a.empty? || b.empty?

      max_len = [a.length, b.length].max
      1.0 - (levenshtein(a, b).to_f / max_len)
    end
  end
end
