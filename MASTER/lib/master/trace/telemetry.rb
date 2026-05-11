# frozen_string_literal: true

require "json"

module Master
  module Trace
  # OpenTelemetry tracer wrapper. Soft-optional — if the SDK isn't loaded,
  # span() degrades to a plain yield. Spans emit JSONL to .master/traces.log.
  module Telemetry
    TRACE_PATH = ".master/traces.log".freeze

    @enabled = false
    @tracer  = nil
    @io      = nil

    class << self
      attr_reader :enabled, :tracer
    end

    def self.bootstrap!(root:, service: "master")
      return if @enabled
      require "opentelemetry/sdk"
      path = File.join(root, TRACE_PATH)
      require "fileutils"
      FileUtils.mkdir_p(File.dirname(path))
      @io = File.open(path, "a")
      @io.sync = true
      OpenTelemetry::SDK.configure do |c|
        c.service_name = service
        c.add_span_processor(
          OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(JsonlExporter.new(@io))
        )
      end
      @tracer  = OpenTelemetry.tracer_provider.tracer(service)
      @enabled = true
    rescue LoadError
      @enabled = false
    rescue StandardError
      @enabled = false
    end

    def self.span(name, attrs = {})
      return yield unless @enabled && @tracer
      @tracer.in_span(name, attributes: stringify(attrs)) { yield }
    rescue StandardError
      yield
    end

    def self.stringify(hash)
      hash.each_with_object({}) { |(k, v), out| out[k.to_s] = v.to_s }
    end

    class JsonlExporter
      SUCCESS = 0
      FAILURE = 1

      def initialize(io)
        @io = io
      end

      def export(spans, timeout: nil)
        spans.each do |s|
          @io.puts(JSON.generate(
            name:    s.name,
            kind:    s.kind.to_s,
            start:   s.start_timestamp,
            end:     s.end_timestamp,
            dur_us:  ((s.end_timestamp - s.start_timestamp) / 1000),
            attrs:   s.attributes,
            trace:   s.hex_trace_id,
            span:    s.hex_span_id
          ))
        end
        SUCCESS
      rescue StandardError
        FAILURE
      end

      def force_flush(timeout: nil) = SUCCESS
      def shutdown(timeout: nil)    = SUCCESS
    end
  end
  end
end
