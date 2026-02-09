# frozen_string_literal: true

module MASTER
  # CircuitBreaker - Rate limiting and failure handling for LLM calls
  # Prevents cascading failures and manages request throttling
  module CircuitBreaker
    extend self

    FAILURES_BEFORE_TRIP = 3
    CIRCUIT_RESET_SECONDS = 300
    RATE_LIMIT_PER_MINUTE = 30

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

    def circuit_closed?(model)
      return true unless defined?(DB)
      row = DB.circuit(model)
      return true unless row

      state = row[:state]
      return true if state == "closed"

      last_failure = row[:last_failure]
      if Time.now.utc - Time.parse(last_failure) > CIRCUIT_RESET_SECONDS
        close_circuit!(model)
        true
      else
        false
      end
    end

    def open_circuit!(model)
      return unless defined?(DB)

      row = DB.circuit(model)
      current_failures = row ? (row[:failures] || 0) + 1 : 1

      if current_failures >= FAILURES_BEFORE_TRIP
        DB.trip!(model)
      else
        # Increment failure count without tripping
        DB.increment_failure!(model)
      end
    end

    def close_circuit!(model)
      DB.reset!(model) if defined?(DB)
    end
  end
end
