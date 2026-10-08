# frozen_string_literal: true

module Master
  module Ground
    # Small reliability primitives used by long-running MASTER operations.
    #
    # The clock is monotonic for deadlines. Wall-clock time may jump when an
    # operator adjusts the host clock or NTP steps it; elapsed work must not.
    module Reliability
      class Deadline
        attr_reader :seconds, :started_at

        def initialize(seconds, clock: Process::CLOCK_MONOTONIC)
          @seconds = Float(seconds)
          raise ArgumentError, "deadline must be positive" unless @seconds.positive?

          @clock = clock
          @started_at = Process.clock_gettime(@clock)
          freeze
        end

        def elapsed = Process.clock_gettime(@clock) - @started_at

        def remaining
          [@seconds - elapsed, 0.0].max
        end

        def expired? = remaining.zero?

        # External collaborators still accept wall-clock deadlines. This value
        # is only an interoperability boundary; expiration decisions stay
        # monotonic through #expired? and #remaining.
        def at = Time.now + remaining

        def to_i = remaining.ceil
      end

      Status = Data.define(:state, :code, :message, :details) do
        STATES = %i[healthy degraded failed].freeze

        def self.healthy(message = nil, details: {}) = new(:healthy, :ok, message, details)
        def self.degraded(message, code: :degraded, details: {}) = new(:degraded, code, message, details)
        def self.failed(message, code: :failure, details: {}) = new(:failed, code, message, details)

        def healthy? = state == :healthy
        def degraded? = state == :degraded
        def failed? = state == :failed
      end
    end
  end
end
