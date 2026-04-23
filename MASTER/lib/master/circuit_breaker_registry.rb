# frozen_string_literal: true

require "monitor"

module Master
  # Registry of per‑model circuit breakers.
  #
  # Each model gets its own +CircuitBreaker+ instance so that a flaky
  # free‑tier endpoint does not affect the failure count of paid fallbacks.
  # Global rate‑limiting is handled by a single shared breaker.
  class CircuitBreakerRegistry
    include MonitorMixin

    # Public: Create a new registry.
    #
    # budget_max: Maximum budget (cost) allowed for a session.
    # req_max:    Maximum number of requests allowed for a session.
    # event_bus:  Optional event bus for publishing breaker events.
    #
    # The arguments are stored frozen to guarantee immutability.
    def initialize(budget_max:, req_max:, event_bus: nil)
      super()
      @defaults = { budget_max: budget_max, req_max: req_max, event_bus: event_bus }.freeze
      @breakers = {} # model_id (String) => CircuitBreaker
      @global   = CircuitBreaker.new(**@defaults)
    end

    # Public: Retrieve the breaker for +model_id+, creating it lazily.
    #
    # model_id - Any object identifying a model; will be converted to a string.
    #
    # Returns a +CircuitBreaker+ instance.
    def for(model_id)
      synchronize do
        @breakers[model_id.to_s] ||= CircuitBreaker.new(**@defaults)
      end
    end

    # Public: Perform a global rate‑limit check.
    #
    # Raises +CircuitBreaker::OpenError+ if the global limit is exceeded.
    def check_rate!
      @global.check_rate!
    end

    # Public: Total cost incurred across all model‑specific breakers plus the
    # global breaker.
    #
    # Returns a numeric cost total.
    def session_total
      synchronize { @breakers.values.sum(&:session_total) + @global.session_total }
    end

    # Public: Record cost against the global breaker.
    #
    # amount - Numeric cost to add.
    def record_cost(amount)
      @global.record_cost(amount)
    end

    # Public: Back‑compatibility shim – behaves like a plain +CircuitBreaker+.
    #
    # cost_estimate - Expected cost of the operation.
    # &blk          - Block to execute if the circuit is closed.
    #
    # Returns whatever the underlying breaker returns.
    def call(cost_estimate, &blk)
      @global.call(cost_estimate, &blk)
    end

    # Public: List model IDs whose breakers are currently open.
    #
    # Returns an Array of model ID strings.
    def open_models
      synchronize do
        @breakers.filter_map do |id, breaker|
          id if breaker.respond_to?(:open?) && breaker.open?
        end
      end
    end
  end
end