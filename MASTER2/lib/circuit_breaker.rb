# frozen_string_literal: true

module MASTER
  # CircuitBreaker - Rate limiting and failure handling for LLM calls
  # Prevents cascading failures and manages request throttling
  # Simple implementation without external dependencies
  module CircuitBreaker
    extend self

    FAILURES_BEFORE_TRIP = 3
    CIRCUIT_RESET_SECONDS = 300
    RATE_LIMIT_PER_MINUTE = 30

    # Circuit breaker states
    @circuits = {}
    @circuits_mutex = Mutex.new

    class << self
      attr_reader :circuits, :circuits_mutex
    end

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
      check_rate_limit!
      
      # Get circuit state
      circuit = get_circuit(model)
      
      if circuit[:state] == :open
        # Check if cool-off period has passed
        if Time.now - circuit[:opened_at] > CIRCUIT_RESET_SECONDS
          set_circuit_state(model, :half_open)
        else
          raise "Circuit breaker open for #{model}"
        end
      end
      
      begin
        result = yield
        
        # Success - reset circuit if it was half_open
        if circuit[:state] == :half_open
          set_circuit_state(model, :closed)
        end
        
        result
      rescue => e
        record_failure(model, e)
        raise
      end
    end

    def open?(model)
      circuit = get_circuit(model)
      circuit[:state] == :open
    end

    def circuit_closed?(model)
      !open?(model)
    end

    def record_failure(model, error)
      self.class.circuits_mutex.synchronize do
        circuit = get_circuit(model)
        circuit[:failures] += 1
        circuit[:last_failure] = Time.now
        
        if circuit[:failures] >= FAILURES_BEFORE_TRIP
          circuit[:state] = :open
          circuit[:opened_at] = Time.now
          log_warning("Circuit breaker opened", model: model, failures: circuit[:failures])
        end
        
        self.class.circuits[model] = circuit
      end
    end

    # Compatibility methods for old API
    def open_circuit!(model)
      record_failure(model, StandardError.new("Circuit breaker tripped"))
    end

    def close_circuit!(model)
      set_circuit_state(model, :closed)
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
    
    def get_circuit(model)
      self.class.circuits_mutex.synchronize do
        self.class.circuits[model] ||= {
          state: :closed,
          failures: 0,
          opened_at: nil,
          last_failure: nil
        }
      end
    end
    
    def set_circuit_state(model, state)
      self.class.circuits_mutex.synchronize do
        circuit = get_circuit(model)
        circuit[:state] = state
        circuit[:failures] = 0 if state == :closed
        self.class.circuits[model] = circuit
      end
    end
  end
end

