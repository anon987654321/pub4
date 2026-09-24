# frozen_string_literal: true

module Master
  module Trace
    class Logging
      DEFAULT_DMESG_LINES = 50
      attr_reader :buffer

      def initialize(ring_buffer:, event_bus:)
        @buffer = ring_buffer
        @bus = event_bus
        @console = Dmesg::Console.new
        @listeners = []
        @mutex = Mutex.new
        wire_events
      end

      def dmesg(lines = DEFAULT_DMESG_LINES)
        @buffer.to_a.last(lines).join("\n")
      end

      # The terminal hears the same lines the ring holds, numbered once: two
      # consoles on one bus would call the same disk sd0 and sd3.
      def listen(&block)
        @mutex.synchronize { @listeners << block }
        -> { @mutex.synchronize { @listeners.delete(block) } }
      end

      private

      def wire_events
        @bus.subscribe("**") { |payload| record(payload) }
      end

      def record(payload)
        units = @mutex.synchronize { @console.lines(payload) }.map { |line| Master::Ground::Redactor.text(line) }
        return @buffer.push(format_entry(payload)) if units.empty?

        units.each { |line| @buffer.push(line) }
        listeners = @mutex.synchronize { @listeners.dup }
        units.each { |line| listeners.each { |listener| listener.call(line) } }
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
        unit = DmesgUnit.name(component)
        details = rest.map { |k, v| "#{k}=#{v}" }.join(" ")
        details = Master::Ground::Redactor.text(details)
        details.empty? ? "#{unit}: #{action}" : "#{unit}: #{action} #{details}"
      end
    end

    module DmesgUnit
      MAP = {
        "llm" => "model0",
        "route" => "model0",
        "infer" => "model0",
        "tool" => "tool0",
        "scan" => "scan0",
        "rule_loop" => "scan0",
        "council" => "council0",
        "git" => "git0",
        "test" => "test0",
        "validation" => "test0",
        "runtime" => "runtime0",
        "pipeline" => "pipeline0",
        "fix_loop" => "fix0",
      }.freeze

      module_function

      def name(component)
        MAP.fetch(component.to_s, "#{component}0")
      end
    end
  end
end
