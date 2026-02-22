# frozen_string_literal: true

module MASTER
  # Functional Result monad (Ok/Err)
  # Provides railway-oriented programming for error handling
  class Result
    # Custom error class for raising within Result flows
    class Error < StandardError; end

    CATEGORIES = %i[infrastructure validation timeout budget axiom_violation unknown].freeze

    attr_reader :value, :error, :kind, :category, :metadata

    # Initialize Result
    # @param value [Object, nil] Success value
    # @param error [String, nil] Error message
    # @param kind [Symbol, nil] Result kind (:ok or :err)
    # @param category [Symbol, nil] Error category (see CATEGORIES)
    # @param metadata [Hash] Additional metadata
    def initialize(value: nil, error: nil, kind: nil, category: nil, metadata: {})
      @value = value
      @error = error
      @kind = kind || (error.nil? ? :ok : :err)
      @category = category || :unknown
      @metadata = metadata
      freeze_state
    end

    # Check if result is successful
    # @return [Boolean] true if ok
    def ok? = @kind == :ok

    # Check if result is error
    # @return [Boolean] true if err
    def err? = @kind == :err

    # Get error (alias for error)
    # @return [String, nil] Error message if err
    def failure = @error

    # Unwrap value or raise error
    # @return [Object] Value if ok
    # @raise [RuntimeError] if err
    def value!
      raise(@error.to_s) if err?
      @value
    end

    # Alias for value!
    # @return [Object] Value if ok
    # @raise [RuntimeError] if err
    def unwrap = value!

    # Get value or return default
    # @param default [Object] Default value if err
    # @return [Object] Value if ok, default if err
    def value_or(default)
      ok? ? @value : default
    end

    # Map over value if ok
    # @yield [Object] Value to transform
    # @return [Result] New result with transformed value or same err
    def map
      return self if err?
      Result.ok(yield(@value))
    rescue StandardError => e
      Result.err(e.message)
    end

    # Flat map over value if ok
    # @yield [Object] Value to transform
    # @return [Result] Result from block or same err
    def flat_map
      return self if err?
      result = yield(@value)
      raise TypeError, "flat_map block must return Result, got #{result.class}" unless result.is_a?(Result)
      result
    rescue TypeError
      raise
    rescue StandardError => e
      Result.err(e.message)
    end

    # Chain operations with labeled error context
    # @param label [String, nil] Label for error context
    # @yield [Object] Value to transform
    # @return [Result] Result from block or labeled err
    def and_then(label = nil)
      return self if err?
      result = yield(@value)
      raise TypeError, "and_then block must return Result, got #{result.class}" unless result.is_a?(Result)
      result
    rescue TypeError
      raise
    rescue StandardError => e
      Result.err("#{label ? "#{label}: " : ""}#{e.message}")
    end

    def inspect
      if ok?
        "#<Result.ok #{@value.inspect}>"
      else
        "#<Result.err(#{@category}) #{@error.inspect}>"
      end
    end

    # Predicate: can this error be retried?
    # @return [Boolean] true for infrastructure or timeout errors
    def retriable?
      err? && %i[infrastructure timeout].include?(@category)
    end

    # Predicate: is this error permanent (no retry)?
    # @return [Boolean] true for validation, axiom_violation, or budget errors
    def permanent?
      err? && %i[validation axiom_violation budget].include?(@category)
    end

    # Predicate: is this an infrastructure error?
    # @return [Boolean] true if category is :infrastructure
    def infrastructure?
      err? && @category == :infrastructure
    end

    class << self
      # Create successful result
      # @param value [Object] Success value (defaults to nil). Callers should check .value before use.
      # @return [Result] Ok result
      def ok(value = nil) = new(value: value, kind: :ok)

      # Create error result
      # @param error [String] Error message
      # @param category [Symbol] Error category (see CATEGORIES)
      # @param metadata [Hash] Additional metadata
      # @return [Result] Err result
      def err(error, category: :unknown, metadata: {})
        new(error: error, kind: :err, category: category, metadata: metadata)
      end

      # Try block and wrap in Result
      # @yield Block to execute
      # @return [Result] Ok with result or Err with error message
      def try
        ok(yield)
      rescue StandardError => e
        err(e.message)
      end
    end

    private

    def freeze_state
      # Deep-dup before freezing to prevent mutation via references
      @value = deep_dup(@value) if @value.is_a?(Hash) || @value.is_a?(Array)
      @value.freeze if @value.is_a?(Hash) || @value.is_a?(Array) || @value.is_a?(String)
      @error.freeze if @error.is_a?(String)
      @category.freeze
      @metadata = deep_dup(@metadata) if @metadata.is_a?(Hash)
      @metadata.freeze
      freeze
    end

    def deep_dup(obj)
      case obj
      when Hash then obj.transform_values { |v| deep_dup(v) }
      when Array then obj.map { |v| deep_dup(v) }
      when Set then Set.new(obj.map { |v| deep_dup(v) })
      when String then obj.dup
      else
        obj.frozen? ? obj : (obj.dup rescue obj)
      end
    end
  end

end
