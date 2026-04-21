# frozen_string_literal: true

require "monitor"

module Master
  # Per-model circuit breaker registry.
  #
  # One CircuitBreaker instance per model endpoint — a flaky free-tier model
  # does not poison the failure count for paid fallbacks.
  #
  # Rate limiting stays global: request volume is per-user, not per-model.
  class CircuitBreakerRegistry
    include MonitorMixin

    def initialize(budget_max:, req_max:, event_bus: nil)
      super()
      @defaults = { budget_max:, req_max:, event_bus: }
      @breakers = {}
      @global   = CircuitBreaker.new(**@defaults)
    end

    # Returns (lazily creating) the CircuitBreaker for a given model key.
    def for(model_id)
      synchronize { @breakers[model_id.to_s] ||= CircuitBreaker.new(**@defaults) }
    end

    # Global rate check — call once per user request, not per model attempt.
    def check_rate! = @global.check_rate!

    # Session cost summed across all per-model breakers.
    def session_total = synchronize { @breakers.values.sum(&:session_total) + @global.session_total }

    def record_cost(amount) = @global.record_cost(amount)

    # Fallback: behave like a plain CircuitBreaker for code that predates the registry.
    def call(cost_estimate, &blk) = @global.call(cost_estimate, &blk)

    def open_models
      synchronize do
        @breakers.filter_map { |id, b| id if b.instance_variable_get(:@state) == :open }
      end
    end
  end
end
