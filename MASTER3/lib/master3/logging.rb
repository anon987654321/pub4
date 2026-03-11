# frozen_string_literal: true

module Master3
  class Logging
    attr_reader :buffer

    def initialize(ring_buffer:, event_bus:, trace_level: 0)
      @buffer      = ring_buffer
      @bus         = event_bus
      # trace_level accepted for API compatibility but not consulted internally;
      # tracing is controlled via Config#trace and ENV["MASTER_TRACE"].

      wire_events
    end

    def dmesg(lines = 50)
      @buffer.to_a.last(lines).join("\n")
    end

    private

    def wire_events
      @bus.subscribe("**") { |payload| @buffer.push(format_entry(payload)) }
    end

    def format_entry(payload)
      event = payload[:event]
      ts    = payload[:ts]
      rest  = payload.except(:event, :ts)
      "[#{ts}ms] #{event}#{rest.empty? ? "" : ": #{rest.inspect}"}"
    end
  end
end
