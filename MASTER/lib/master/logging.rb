# frozen_string_literal: true

module Master
  class Logging
    DEFAULT_DMESG_LINES = 50
    attr_reader :buffer

    def initialize(ring_buffer:, event_bus:, trace_level: 0)
      @buffer      = ring_buffer
      @bus         = event_bus
      # trace_level accepted for API compatibility but not consulted internally;
      # tracing is controlled via Config#trace and ENV["MASTER_TRACE"].

      wire_events
    end

    def dmesg(lines = DEFAULT_DMESG_LINES)
      @buffer.to_a.last(lines).join("\n")
    end

    private

    def wire_events
      @bus.subscribe("**") { |payload| @buffer.push(format_entry(payload)) }
    end

    def format_entry(payload)
      event = payload[:event].to_s
      rest  = payload.except(:event, :ts)

      parts = event.split(":")
      component = parts[0]
      action = parts[1] || "ready"

      details = rest.map { |k, v| "#{k}=#{v}" }.join(", ")
      details.empty? ? "#{component}: #{action}" : "#{component}: #{action}, #{details}"
    end
  end
end
