# frozen_string_literal: true

require "stoplight"

module MASTER
  # CircuitBreaker - Rate limiting and failure handling for LLM calls
  # Prevents cascading failures and manages request throttling
  module CircuitBreaker
    extend self

    FAILURES_BEFORE_TRIP = 3
    CIRCUIT_RESET_SECONDS = 300
    RATE_LIMIT_PER_MINUTE = 30

    # Initialize stoplight with memory data store
    Stoplight.default_data_store = Stoplight::DataStore::Memory.new

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
            Logging.warn("Rate limit reached, waiting", seconds: wait_time.round) if defined?(Logging)
            sleep(wait_time)
            state[:requests].clear
          end
        end
        
        state[:requests] << now
      end
    end

    def run(model, &block)
      Stoplight("openrouter-#{model}")
        .with_threshold(FAILURES_BEFORE_TRIP)
        .with_cool_off_time(CIRCUIT_RESET_SECONDS)
        .run(&block)
    end

    def open?(model)
      light = Stoplight("openrouter-#{model}")
      light.color == Stoplight::Color::RED
    end

    def circuit_closed?(model)
      !open?(model)
    end

    def record_failure(model, error)
      Stoplight("openrouter-#{model}")
        .with_threshold(FAILURES_BEFORE_TRIP)
        .with_cool_off_time(CIRCUIT_RESET_SECONDS)
        .run { raise error }
    rescue Stoplight::Error::RedLight
      # Circuit is now open
    end

    # Compatibility methods for old API
    def open_circuit!(model)
      record_failure(model, StandardError.new("Circuit breaker tripped"))
    end

    def close_circuit!(model)
      # Stoplight handles this automatically based on cool_off_time
    end
  end
end

