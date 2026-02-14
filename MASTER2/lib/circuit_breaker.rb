# frozen_string_literal: true

# Try to load Stoplight, fall back to simple implementation if not available
begin
  require "stoplight"
  STOPLIGHT_AVAILABLE = true
rescue LoadError
  STOPLIGHT_AVAILABLE = false
  
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
    
    def initialize(name, threshold = 3, cool_off_time = 300)
      @name = name
      @threshold = threshold
      @cool_off_time = cool_off_time
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

    # Check if circuit is closed for a model (P2 fix #7: use Stoplight execution)
    def circuit_closed?(model)
      light = Stoplight("llm-#{model}", threshold: FAILURES_BEFORE_TRIP, cool_off_time: CIRCUIT_RESET_SECONDS)
      begin
        light.run { PROBE_VALUE }
        true
      rescue Stoplight::Error::RedLight
        false
      end
    end

    # Run a block with circuit breaker protection (backward compatibility for tests)
    def run(model, &block)
      check_rate_limit!

      light = Stoplight("llm-#{model}", threshold: FAILURES_BEFORE_TRIP, cool_off_time: CIRCUIT_RESET_SECONDS)

      light.run(&block)
    end

    # P1 fix #1: Record only ONE failure per request (not in a loop)
    def open_circuit!(model)
      # Note: In Stoplight v4/v5, we cannot directly access default_data_store to record failures.
      # Instead, we use the execution API to trigger a failure. This is the recommended approach
      # when the data store API is not available or has changed between versions.
      # The circuit breaker will record this as a failure and potentially trip the circuit.
      light = Stoplight("llm-#{model}", threshold: FAILURES_BEFORE_TRIP, cool_off_time: CIRCUIT_RESET_SECONDS)
      
      begin
        light.run { raise TestFailure, "Intentional failure for circuit breaker state management" }
      rescue TestFailure, Stoplight::Error::RedLight
        # Expected - TestFailure triggers the failure, RedLight means circuit was already open
      end
    rescue StandardError => e
      Logging.warn("Failed to open circuit", model: model, error: e.message)
    end

    # P2 fix #8: Add nil check and rescue in close_circuit!
    def close_circuit!(model)
      # Note: In Stoplight v4/v5, successful runs automatically clear failure counts.
      # We cannot directly access default_data_store.clear_failures() in v5.
      # Per Stoplight documentation, running a successful execution is the standard way
      # to reset the circuit breaker state. The PROBE_VALUE ensures a no-op execution.
      light = Stoplight("llm-#{model}", threshold: FAILURES_BEFORE_TRIP, cool_off_time: CIRCUIT_RESET_SECONDS)
      
      begin
        light.run { PROBE_VALUE }
      rescue Stoplight::Error::RedLight
        # Circuit may still be open, that's ok
      end
    rescue StandardError => e
      Logging.warn("Failed to close circuit", model: model, error: e.message)
    end
  end
end
