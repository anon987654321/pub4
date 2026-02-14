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
  
  def Stoplight(name)
    StoplightMock.new(name)
  end
  
  class StoplightMock
    attr_reader :name
    
    def initialize(name)
      @name = name
      @threshold = 3
      @cool_off_time = 300
    end
    
    def with_threshold(n)
      @threshold = n
      self
    end
    
    def with_cool_off_time(seconds)
      @cool_off_time = seconds
      self
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
            log_warning("Rate limit reached, waiting", seconds: wait_time.round)
            sleep(wait_time)
            state[:requests].clear
          end
        end

        state[:requests] << now
      end
    end

    # Check if circuit is closed for a model (P2 fix #7: use Stoplight execution)
    def circuit_closed?(model)
      light = Stoplight("llm-#{model}")
                .with_threshold(FAILURES_BEFORE_TRIP)
                .with_cool_off_time(CIRCUIT_RESET_SECONDS)
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

      light = Stoplight("llm-#{model}")
                .with_threshold(FAILURES_BEFORE_TRIP)
                .with_cool_off_time(CIRCUIT_RESET_SECONDS)

      light.run(&block)
    end

    # P1 fix #1: Record only ONE failure per request (not in a loop)
    def open_circuit!(model)
      # Record failure using Stoplight's data store API directly
      # This is more idiomatic than raising/catching exceptions
      light = Stoplight("llm-#{model}")
                .with_threshold(FAILURES_BEFORE_TRIP)
                .with_cool_off_time(CIRCUIT_RESET_SECONDS)
      
      data_store = Stoplight::Light.default_data_store
      return unless data_store
      
      # Record a failure for this circuit
      data_store.record_failure(light)
    rescue StandardError => e
      log_warning("Failed to open circuit", model: model, error: e.message)
    end

    # P2 fix #8: Add nil check and rescue in close_circuit!
    def close_circuit!(model)
      data_store = Stoplight::Light.default_data_store
      return unless data_store&.respond_to?(:clear_failures)

      light = Stoplight("llm-#{model}")
                .with_threshold(FAILURES_BEFORE_TRIP)
                .with_cool_off_time(CIRCUIT_RESET_SECONDS)
      
      data_store.clear_failures(light)
    rescue StandardError => e
      log_warning("Failed to close circuit", model: model, error: e.message)
    end

    private

    def log_warning(message, **args)
      if defined?(Logging)
        Logging.warn(message, **args)
      else
        # Fallback to stderr if Logging not available
        warn "#{message}: #{args.inspect}"
      end
    end
  end
end
