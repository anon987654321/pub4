# frozen_string_literal: true

module CircuitBreaker
  class OpenCircuitError < StandardError; end

  class Breaker
    DEFAULT_FAILURE_THRESHOLD = 5
    DEFAULT_RESET_TIMEOUT = 60
    HALF_OPEN_MAX_TRIALS = 1

    STATE_CLOSED = :closed
    STATE_OPEN = :open
    STATE_HALF_OPEN = :half_open

    def initialize(failure_threshold: DEFAULT_FAILURE_THRESHOLD, reset_timeout: DEFAULT_RESET_TIMEOUT)
      @failure_threshold = failure_threshold
      @reset_timeout = reset_timeout

      @mutex = Mutex.new
      @state = STATE_CLOSED
      @failure_count = 0
      @opened_at = nil
      @half_open_trials = 0
    end

    def call
      @mutex.synchronize { reset_if_timeout! }
      raise OpenCircuitError, "circuit is open" unless allow_request?

      begin
        result = yield
      rescue StandardError
        record_failure
        raise
      end

      record_success
      result
    end

    def state
      @mutex.synchronize { @state }
    end

    private

    def allow_request?
      @mutex.synchronize do
        return true if @state == STATE_CLOSED
        return false if @state == STATE_OPEN
        return false if @half_open_trials >= HALF_OPEN_MAX_TRIALS

        @half_open_trials += 1
        true
      end
    end

    def record_success
      @mutex.synchronize do
        close!
      end
    end

    def record_failure
      @mutex.synchronize do
        @failure_count += 1
        open! if @failure_count >= @failure_threshold
      end
    end

    def open!
      @state = STATE_OPEN
      @opened_at = Time.now
      @half_open_trials = 0
    end

    def half_open!
      @state = STATE_HALF_OPEN
      @failure_count = 0
      @half_open_trials = 0
    end

    def close!
      @state = STATE_CLOSED
      @failure_count = 0
      @opened_at = nil
      @half_open_trials = 0
    end

    def reset_if_timeout!
      return unless @state == STATE_OPEN
      return unless @opened_at
      return unless (Time.now - @opened_at) >= @reset_timeout

      half_open!
    end
  end
end