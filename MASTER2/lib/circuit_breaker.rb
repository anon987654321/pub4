# frozen_string_literal: true

require "stoplight"

module MASTER
  # Circuit breaker backed by Stoplight gem
  # Preserves existing API for backward compatibility
  module CircuitBreaker
    extend self

    FAILURES_BEFORE_TRIP = 3
    CIRCUIT_RESET_SECONDS = 300
    RATE_LIMIT_PER_MINUTE = 30

    @request_times = []
    @mutex = Mutex.new

    Stoplight.default_data_store = Stoplight::DataStore::Memory.new

    def circuit_closed?(model)
      light = Stoplight(model)
        .with_threshold(FAILURES_BEFORE_TRIP)
        .with_cool_off_time(CIRCUIT_RESET_SECONDS)
      light.color != Stoplight::Color::RED
    end

    def open_circuit!(model)
      light = Stoplight(model)
        .with_threshold(FAILURES_BEFORE_TRIP)
        .with_cool_off_time(CIRCUIT_RESET_SECONDS)
      light.record_failure(Stoplight::Error::RedLight.new)
    end

    def close_circuit!(model)
      light = Stoplight(model)
        .with_threshold(FAILURES_BEFORE_TRIP)
        .with_cool_off_time(CIRCUIT_RESET_SECONDS)
      light.record_success
    end

    def check_rate_limit!
      @mutex.synchronize do
        now = Time.now
        @request_times.reject! { |t| now - t > 60 }
        if @request_times.size >= RATE_LIMIT_PER_MINUTE
          raise "Rate limit exceeded (#{RATE_LIMIT_PER_MINUTE}/min)"
        end
        @request_times << now
      end
    end

    def status
      { rate_limit: { current: @request_times.size, max: RATE_LIMIT_PER_MINUTE } }
    end
  end
end
