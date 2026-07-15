# frozen_string_literal: true

module Master
  module Trace
    class Logging
      DEFAULT_DMESG_LINES = 50
      attr_reader :buffer

      def initialize(ring_buffer:, event_bus:)
        @buffer = ring_buffer
        @bus = event_bus
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
        if event.start_with?("tool:") && payload[:path]
          op = payload.fetch(:op) { event.split(":", 2).last }
          bytes = payload[:bytes] ? " #{payload[:bytes]}B" : ""
          path = Master::Ground::Redactor.text(payload[:path].to_s)
          return "tool: #{op} #{path}#{bytes}"
        end

        rest = Master::Ground::Redactor.payload(payload.except(:event, :ts))
        component, action = event.split(":", 2)
        action ||= "ready"
        details = rest.map { |k, v| "#{k}=#{v}" }.join(" ")
        details = Master::Ground::Redactor.text(details)
        details.empty? ? "#{component}: #{action}" : "#{component}: #{action} #{details}"
      end
    end
  end
end
