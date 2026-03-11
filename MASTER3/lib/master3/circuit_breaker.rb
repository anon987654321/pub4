# frozen_string_literal: true

require "monitor"

module Master3
  class CircuitBreaker
    include MonitorMixin

    FAILURE_THRESHOLD = 3
    COOLDOWN_S        = 30
    RATE_WINDOW_S     = 60
    RATE_MAX          = 30

    class CircuitError < StandardError
      attr_reader :category
      def initialize(msg, category) = (super(msg); @category = category)
    end

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
      @mutex         = Mutex.new
    end

    def call(cost_estimate, &blk)
      check_rate
      check_budget(cost_estimate)
      check_circuit
      result = blk.call
      on_success
      result
    rescue CircuitError => e
      on_failure
      Result.err(e.message, category: e.category)
    rescue RubyLLM::RateLimitError => e
      # Rate limits don't indicate upstream failure — don't trip the circuit
      Result.err("rate_limit: #{e.message}", category: :infrastructure)
    rescue => e
      on_failure
      Result.err("circuit: #{e.message}", category: :unknown)
    end

    def record_cost(amount)  = synchronize { @session_total += amount }
    def session_total        = synchronize { @session_total }

    private

    def check_rate
      synchronize do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @req_times.reject! { |t| now - t > RATE_WINDOW_S }
        raise CircuitError.new("rate limit: #{RATE_MAX} req/min exceeded", :infrastructure) if @req_times.size >= RATE_MAX
        @req_times << now
      end
    end

    def check_budget(estimate)
      return if @budget_max <= 0
      synchronize do
        raise CircuitError.new("budget: $#{(@session_total + estimate).round(4)} would exceed $#{@budget_max}", :budget) if @session_total + estimate > @budget_max
      end
    end

    def check_circuit
      synchronize do
        return if @state == :closed
        if @state == :open
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @opened_at
          if elapsed >= COOLDOWN_S
            @state = :half_open
          else
            raise CircuitError.new("circuit open: retry in #{(COOLDOWN_S - elapsed).ceil}s", :infrastructure)
          end
        end
      end
    end

    def on_success = synchronize { @failures = 0 ; @state = :closed if @state == :half_open }
    def on_failure = synchronize { @failures += 1 ; @state = :open ; @opened_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) if @failures >= FAILURE_THRESHOLD }
  end
end
