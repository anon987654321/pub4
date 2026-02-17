# frozen_string_literal: true

# Try to load Stoplight, fall back to simple implementation if not available
begin
  require "stoplight"
rescue LoadError
  # Simple mock for when Stoplight is not available
  module Stoplight
    class Light
      def self.default_data_store
        nil
      end
    end

    module Error
      class RedLight < StandardError; end
    end
  end

  def Stoplight(name, threshold: 3, cool_off_time: 300)
    StoplightMock.new(name, threshold, cool_off_time)
  end

  class StoplightMock
    attr_reader :name

    @warned = false

    class << self
      attr_accessor :warned
    end

    def initialize(name, threshold = 3, cool_off_time = 300)
      @name = name
      @threshold = threshold
      @cool_off_time = cool_off_time
      unless self.class.warned
        warn "Warning: Stoplight gem not available - circuit breaker disabled"
        self.class.warned = true
      end
    end

    def run
      yield
    end
  end
end

module MASTER
  # CircuitBreaker - Rate limiting and failure handling for LLM calls using Stoplight
  # Prevents cascading failures and manages request throttling
  module CircuitBreaker
    extend self
    # Custom exception for intentional circuit breaker state changes
    class TestFailure < StandardError; end

    FAILURES_BEFORE_TRIP = 3
    CIRCUIT_RESET_SECONDS = 300
    RATE_LIMIT_PER_MINUTE = 30
    # Value used to test circuit state without side effects
    PROBE_VALUE = :probe

    # Rate limiting state
    @rate_limit_mutex = Mutex.new
    @rate_limit_state = { requests: [], window_start: Time.now }

    class << self
      attr_reader :rate_limit_mutex, :rate_limit_state
    end

    def rate_limit_state
      @rate_limit_state
    end

    def check_rate_limit!
      @rate_limit_mutex.synchronize do
        now = Time.now
        state = rate_limit_state

        # Clean old requests (older than 1 minute)
        state[:requests].reject! { |t| now - t > 60 }

        if state[:requests].size >= RATE_LIMIT_PER_MINUTE
          oldest = state[:requests].min
          wait_time = 60 - (now - oldest)
          if wait_time > 0
            Logging.warn("Rate limit reached, waiting", seconds: wait_time.round)
            sleep(wait_time)
            state[:requests].clear
          end
        end

        state[:requests] << now
      end
    end

    # Build a Stoplight light with standard thresholds
    # Supports Stoplight 4.x (chained), 5.x (keyword args, chained deprecated), 6.x+ (keyword only)
    # Build or retrieve cached Stoplight instance for a model
    def build_light(model)
      @lights_mutex ||= Mutex.new
      @lights ||= {}
      @lights_mutex.synchronize { return @lights[model] if @lights[model] }
      @lights_mutex.synchronize do
        @lights[model] ||= begin
          Stoplight("llm-#{model}", threshold: FAILURES_BEFORE_TRIP, cool_off_time: CIRCUIT_RESET_SECONDS)
        rescue ArgumentError
          Stoplight("llm-#{model}").with_threshold(FAILURES_BEFORE_TRIP).with_cool_off_time(CIRCUIT_RESET_SECONDS)
        end
      end
    end

    # Check if circuit is closed for a model
    def circuit_closed?(model)
      light = build_light(model)
      begin
        light.run { PROBE_VALUE }
        true
      rescue Stoplight::Error::RedLight
        false
      end
    end

    # Run a block with circuit breaker protection
    def run(model, &block)
      check_rate_limit!
      build_light(model).run(&block)
    end

    # Record a failure to potentially trip the circuit
    def open_circuit!(model)
      light = build_light(model)
      begin
        light.run { raise TestFailure, "Intentional circuit breaker trip" }
      rescue TestFailure, Stoplight::Error::RedLight
        # Expected
      end
    rescue StandardError => e
      Logging.warn("Failed to open circuit", model: model, error: e.message)
    end

    # Run a successful probe to clear failure counts
    def close_circuit!(model)
      light = build_light(model)
      begin
        light.run { PROBE_VALUE }
      rescue Stoplight::Error::RedLight
        # Circuit may still be open
      end
    rescue StandardError => e
      Logging.warn("Failed to close circuit", model: model, error: e.message)
    end
  end
end
