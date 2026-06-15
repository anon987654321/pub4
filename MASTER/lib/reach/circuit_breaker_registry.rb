# frozen_string_literal: true

require "monitor"

module Master
  module Reach
    # Per-model circuit breakers so a flaky free-tier endpoint doesn't affect paid fallbacks.
    class CircuitBreakerRegistry
      include MonitorMixin

      def initialize(budget_max:, req_max:, warn_at: nil, max_per_file: nil, event_bus: nil,
                     state_path: File.join(Master::ROOT, ".master", "circuit_state.yml"))
        super()
        @state_path = state_path
        @defaults = {
          budget_max: budget_max,
          req_max: req_max,
          warn_at: warn_at,
          max_per_file: max_per_file,
          event_bus: event_bus,
          state_path: state_path
        }.freeze
        @breakers = {}
        @global = CircuitBreaker.new(**@defaults.merge(state_key: "global"))
      end

      def for(model_id)
        synchronize do
          @breakers[model_id.to_s] ||= CircuitBreaker.new(
            **@defaults.merge(rate_window_s: CircuitBreaker::RATE_WINDOW_S, state_key: state_key(model_id))
          )
        end
      end

      def check_rate!(model_id = nil)
        synchronize do
          @global.check_rate!
          self.for(model_id).check_rate! if model_id
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

      def state_key(model_id)
        "model:#{model_id.to_s.gsub(/[^a-zA-Z0-9_.-]/, "_")}"
      end
    end
  end
end
