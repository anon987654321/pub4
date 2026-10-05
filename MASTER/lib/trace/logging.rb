# frozen_string_literal: true

module Master
  module Trace
    module DmesgUnit
      ATTACHED = %w[
        llm route infer tool scan law_loop council git test validation runtime pipeline fix_loop
      ].freeze

      MAP = {
        "llm" => "model0",
        "route" => "model0",
        "infer" => "model0",
        "tool" => "tool0",
        "scan" => "scan0",
        "law_loop" => "scan0",
        "council" => "council0",
        "git" => "git0",
        "test" => "test0",
        "validation" => "test0",
        "runtime" => "runtime0",
        "pipeline" => "pipeline0",
        "fix_loop" => "fix0",
        "event_bus" => "event0",
        "swallow" => "error0",
        "boot" => "boot0",
        "cli" => "cli0",
        "tts" => "voice0",
      }.freeze

      module_function

      def unit_name(component)
        MAP.fetch(component.to_s, "#{component}0")
      end
    end

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
        return [] if Thread.current.thread_variable_get(:master_trace_logging_active)

        Thread.current.thread_variable_set(:master_trace_logging_active, true)
        begin
          units = @mutex.synchronize { @console.lines(payload) }.map { |line| Master::Ground::Redactor.text(line) }
          return @buffer.push(format_entry(payload)) if units.empty?

          units.each { |line| @buffer.push(line) }
          listeners = @mutex.synchronize { @listeners.dup }
          units.each { |line| listeners.each { |listener| listener.call(line) } }
        rescue StandardError => e
          warn_logging_failure(e)
          safe_line = "trace0: logging failed — #{e.class}: #{e.message}"
          begin
            @buffer.push(safe_line)
          rescue StandardError
            nil
          end
          []
        ensure
          Thread.current.thread_variable_set(:master_trace_logging_active, false)
        end
      end

      def warn_logging_failure(error)
        return if @logger_failure_warned

        @logger_failure_warned = true
        Master::Trace::Dmesg.once("trace0", "logging degraded, #{error.class}: #{error.message}")
      rescue StandardError
        nil
      end

      def format_entry(payload)
        event = payload[:event].to_s
        component, action = event.split(":", 2)
        action ||= "ready"
        unit = DmesgUnit.unit_name(component)
        parent = Fiber[:master_unit] || "master0"
        rest = Master::Ground::Redactor.payload(payload.except(:event, :ts))
        details = rest.map do |key, value|
          "#{key.to_s.tr("_", " ")} #{value}"
        end.join(", ")
        details = Master::Ground::Redactor.text(details)
        attached = DmesgUnit::ATTACHED.include?(component.to_s)
        prefix = attached && parent != unit ? "#{unit} at #{parent}: #{action}" : "#{unit}: #{action}"
        details.empty? ? prefix : "#{prefix}, #{details}"
      end
    end

  end
end
