# frozen_string_literal: true

require "stoplight"

module MASTER
  # CircuitBreaker - Rate limiting and failure handling for LLM calls using Stoplight
  # Prevents cascading failures and manages request throttling
  module CircuitBreaker
    extend self

    FAILURES_BEFORE_TRIP = 3
    CIRCUIT_RESET_SECONDS = 300
    RATE_LIMIT_PER_MINUTE = 30

    # Configure stoplight defaults
    # NOTE: This is a global configuration that affects all Stoplight usage in the application
    # If other parts of the codebase use Stoplight, they will share this error notifier
    Stoplight.default_error_notifier = ->(light, from_color, to_color, error) {
      log_warning("Circuit breaker state changed", light: light.name, from: from_color, to: to_color)
    }

    # Rate limiting state
    def rate_limit_state
      @rate_limit_state ||= { requests: [], window_start: Time.now }
    end

    def check_rate_limit!
      @rate_limit_mutex ||= Mutex.new
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

    def circuit_closed?(model)
      # Check if circuit is closed by examining the light's color
      # Note: This checks stored state, not by executing the light
      light = Stoplight("llm-#{model}")
        .with_threshold(FAILURES_BEFORE_TRIP)
        .with_cool_off_time(CIRCUIT_RESET_SECONDS)
      
      # Green = closed, red = open, yellow = half-open
      light.color == "green" || light.color == "yellow"
    end

    # Compatibility methods for old API
    def open_circuit!(model)
      # Force circuit open by recording enough failures
      light = Stoplight("llm-#{model}")
        .with_threshold(FAILURES_BEFORE_TRIP)
        .with_cool_off_time(CIRCUIT_RESET_SECONDS)
      
      # Execute multiple times to trip the circuit
      FAILURES_BEFORE_TRIP.times do
        begin
          light.run { raise "Circuit forced open" }
        rescue Stoplight::Error::RedLight, RuntimeError
          # Expected - failures recorded
        end
      end
    end

    def close_circuit!(model)
      # Reset the circuit by clearing its state
      data_store = Stoplight.default_data_store
      light = Stoplight("llm-#{model}")
      data_store.clear_failures(light)
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

