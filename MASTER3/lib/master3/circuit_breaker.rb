# frozen_string_literal: true

require "monitor"

module Master3
  class CircuitBreaker
    include MonitorMixin

    FAILURE_THRESHOLD = 3
    COOLDOWN_S        = 300
    RATE_WINDOW_S     = 60
    RATE_MAX          = 30

    def initialize(budget_max:, req_max:, event_bus: nil)
      super()
      @budget_max    = budget_max
      @req_max       = req_max
      @bus           = event_bus
      @failures      = 0
      @opened_at     = nil
      @state         = :closed
      @session_total = 0.0
      @req_times     = []
    end

    def call(cost_estimate, &blk)
      check_rate!
      check_budget!(cost_estimate)
      check_circuit!
      result = blk.call
      on_success(result)
      result
    rescue Result::Err => e
      on_failure(e)
      e
    end

    def record_cost(amount)
      synchronize { @session_total += amount }
    end

    def session_total = synchronize { @session_total }

    private

    def check_rate!
      synchronize do
        now  = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @req_times.reject! { |t| now - t > RATE_WINDOW_S }
        if @req_times.size >= RATE_MAX
          raise Result::Err.new("rate limit: #{RATE_MAX} req/min exceeded", :infrastructure)
        end
        @req_times << now
      end
    end

    def check_budget!(estimate)
      return if @budget_max <= 0
      synchronize do
        if @session_total + estimate > @budget_max
          raise Result::Err.new("budget: $#{@session_total + estimate} would exceed $#{@budget_max}", :budget)
        end
      end
    end

    def check_circuit!
      synchronize do
        case @state
        when :open
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @opened_at
          if elapsed >= COOLDOWN_S
            @state = :half_open
          else
            raise Result::Err.new("circuit open: retry in #{(COOLDOWN_S - elapsed).ceil}s", :infrastructure)
          end
        end
      end
    end

    def on_success(result)
      synchronize do
        @failures = 0
        @state    = :closed if @state == :half_open
      end
    end

    def on_failure(err)
      synchronize do
        @failures += 1
        if @failures >= FAILURE_THRESHOLD
          @state     = :open
          @opened_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
