# frozen_string_literal: true

require "thread"

module Master
  module Io
    # Bounded in-process concurrency for providers with a documented or
    # operator-declared simultaneous-request limit. This is not a token quota:
    # it prevents MASTER from exceeding its own chosen parallelism ceiling.
    module ProviderConcurrency
      class Saturated < StandardError; end

      class Gate
        attr_reader :limit

        def initialize(limit:)
          @limit = Integer(limit)
          raise ArgumentError, "provider concurrency limit must be positive" unless @limit.positive?

          @in_flight = 0
          @mutex = Mutex.new
          @available = ConditionVariable.new
        end

        def synchronize(wait_seconds:)
          deadline = monotonic_now + [Float(wait_seconds), 0.0].max

          @mutex.synchronize do
            while @in_flight >= @limit
              remaining = deadline - monotonic_now
              raise Saturated, "provider concurrency queue is full" unless remaining.positive?

              @available.wait(@mutex, remaining)
            end
            @in_flight += 1
          end

          begin
            yield
          ensure
            @mutex.synchronize do
              @in_flight -= 1
              @available.signal
            end
          end
        end

        private

        def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      @gates = {}
      @mutex = Mutex.new

      module_function

      # bucket is the actual shared concurrency boundary, not necessarily the
      # model name. Endpoints sharing one provider account can use one bucket.
      def with_slot(bucket:, limit:, wait_seconds: 15)
        max = Integer(limit)
        raise ArgumentError, "provider concurrency limit must be positive" unless max.positive?

        key = bucket.to_s
        raise ArgumentError, "provider quota bucket must not be empty" if key.empty?

        gate = @mutex.synchronize do
          existing = @gates[key]
          if existing && existing.limit != max
            raise ArgumentError, "provider quota bucket #{key.inspect} has conflicting concurrency limits"
          end

          @gates[key] ||= Gate.new(limit: max)
        end
        gate.synchronize(wait_seconds:) { yield }
      end
    end
  end
end
