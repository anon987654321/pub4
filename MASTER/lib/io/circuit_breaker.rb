# frozen_string_literal: true

require "monitor"
require "fileutils"
require "yaml"

module Master
  module Io
    class CircuitBreaker
      include MonitorMixin

      FAILURE_THRESHOLD = 8
      COOLDOWN_S = 30
      RATE_WINDOW_S = 60
      RATE_MAX = 60

      class CircuitError < StandardError
        attr_reader :category
        def initialize(msg, category) = (super(msg); @category = category)
      end

      def initialize(budget_max:, req_max:, event_bus: nil, rate_window_s: RATE_WINDOW_S, rate_max: nil,
                     warn_at: nil, max_per_file: nil, state_path: nil, state_key: "global")
        super()
        @budget_max = budget_max
        @warn_at = warn_at
        @max_per_file = max_per_file
        @bus = event_bus
        @failures = 0
        @opened_at = nil
        @state = :closed
        @session_total = 0.0
        @req_times = []
        @rate_window = rate_window_s
        @rate_max = normalize_rate_max(rate_max || req_max)
        @state_path = state_path
        @state_key = state_key.to_s
        load_state
      end

      def check_rate!
        synchronize do
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @req_times.reject! { |t| now - t > @rate_window }
          over_rate = @req_times.size >= @rate_max
          raise CircuitError.new("rate limit: #{@rate_max} req/min exceeded", :rate_limit) if over_rate
          @req_times << now
        end
      end

      def call(cost_estimate, &blk)
        check_budget(cost_estimate)
        check_circuit
        result = execute_with_tracking(blk)
        record_cost(cost_estimate) if Result.wrap(result).ok?
        result
      rescue CircuitError => e
        # Budget/circuit-open errors are not backend failures — don't penalize.
        Result.err(e.message, category: e.category)
      end

      def record_cost(amount) = synchronize { @session_total += amount }
      def session_total = synchronize { @session_total }

      def state = synchronize { @state }

      private

      def execute_with_tracking(blk)
        result = blk.call
        on_success
        result
      rescue RubyLLM::RateLimitError => e
        # API rate limit is infrastructure noise — don't open the circuit.
        Result.err("rate_limit: #{e.message}", category: :rate_limit)
      rescue StandardError => e
        error_message = e.message.to_s
        # Config errors aren't backend failures — don't penalize the breaker.
        if !Master.keyless_llm_enabled? &&
           (error_message.match?(/missing configuration/i) || !Master.any_api_key_present?)
          return Result.err(Master.no_api_key_message, category: :no_api_key)
        end
        on_failure
        Result.err(error_message, category: :provider_error)
      end

      def check_budget(estimate)
        return unless @budget_max.positive?
        synchronize do
          projected = @session_total + estimate
          if @max_per_file && estimate > @max_per_file
            raise CircuitError.new("budget: single call $#{estimate.round(4)} exceeds max_per_file $#{@max_per_file}", :budget)
          end
          if @warn_at && projected >= @warn_at && @session_total < @warn_at
            @bus&.publish("budget:warn", projected:, warn_at: @warn_at)
          end
          raise CircuitError.new("budget: $#{projected.round(4)} exceeds $#{@budget_max}", :budget) if projected > @budget_max
        end
      end

      def check_circuit
        # No retry loop here — caller decides whether to retry after catching CircuitError.
        synchronize do
          return if @state == :closed
          if @state == :open
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @opened_at
            unless elapsed >= COOLDOWN_S
              raise CircuitError.new("circuit open: #{(COOLDOWN_S - elapsed).ceil}s cooldown remaining", :infrastructure)
            end
            @state = :half_open
            @failures = 0
            persist_state
          end
        end
      end

      def on_success
        synchronize do
          @failures = 0
          if @state == :half_open
            @state = :closed
            persist_state
            @bus&.publish("circuit:closed", breaker: object_id)
          end
        end
      end

      def on_failure
        synchronize do
          @failures += 1
          return unless @failures >= FAILURE_THRESHOLD
          @state = :open
          @opened_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @opened_wall_at = Time.now.to_f
          persist_state
          @bus&.publish("circuit:open", failures: @failures)
        end
      end

      def load_state
        return unless @state_path && File.exist?(@state_path)

        data = YAML.safe_load_file(@state_path, aliases: true) || {}
        record = data[@state_key] || {}
        restored_state = record["state"].to_s
        return unless restored_state == "open"

        elapsed = Time.now.to_f - record["opened_wall_at"].to_f
        return if elapsed >= COOLDOWN_S

        @state = :open
        @failures = record["failures"].to_i
        @opened_wall_at = record["opened_wall_at"].to_f
        @opened_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) - elapsed
      rescue StandardError => e
        @bus&.publish("circuit:state_load_error", key: @state_key, error: e.message)
      end

      def persist_state
        return unless @state_path

        FileUtils.mkdir_p(File.dirname(@state_path))
        data = File.exist?(@state_path) ? YAML.safe_load_file(@state_path, aliases: true) || {} : {}
        data[@state_key] = {
          "state" => @state.to_s,
          "failures" => @failures,
          "opened_wall_at" => @opened_wall_at,
        }
        File.write(@state_path, YAML.dump(data))
      rescue StandardError => e
        @bus&.publish("circuit:state_persist_error", key: @state_key, error: e.message)
      end

      def normalize_rate_max(value)
        n = value.to_i
        n.positive? ? n : RATE_MAX
      end
    end
  end
end
