# frozen_string_literal: true

require "monitor"

module Master
  # Per-model circuit breakers so a flaky free-tier endpoint doesn't affect paid fallbacks.
  class CircuitBreakerRegistry
    include MonitorMixin

    def initialize(budget_max:, req_max:, event_bus: nil)
      super()
      @defaults = { budget_max: budget_max, req_max: req_max, event_bus: event_bus }.freeze
      @breakers = {}
      @global   = CircuitBreaker.new(**@defaults)
    end

    def for(model_id)
      synchronize do
        @breakers[model_id.to_s] ||= CircuitBreaker.new(
          **@defaults.merge(rate_window_s: CircuitBreaker::RATE_WINDOW_S, rate_max: CircuitBreaker::RATE_MAX)
        )
      end
    end

    def check_rate!
      synchronize do
        @breakers.values.each(&:check_rate!)
        @global.check_rate!
      end
    end

    def session_total
      synchronize { @breakers.values.sum(&:session_total) + @global.session_total }
    end

    def record_cost(amount)
      @global.record_cost(amount)
    end

    def call(cost_estimate, &blk)
      @global.call(cost_estimate, &blk)
    end

    def open_models
      synchronize { @breakers.filter_map { |id, breaker| id if breaker.state == :open } }
    end
  end
end
