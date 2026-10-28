# frozen_string_literal: true

require "json"
require_relative "log"

module Master
  module Trace
  # Soft-optional OpenTelemetry wrapper; span() degrades to plain yield when SDK absent.
    module Telemetry
      TRACE_PATH = "log/traces.log".freeze

      @enabled = false
      @tracer = nil

      class << self
        attr_reader :enabled, :tracer
      end

      def self.bootstrap!(root:, service: "master")
        return if @enabled
        path = File.join(root, TRACE_PATH)
        OpenTelemetry::SDK.configure do |c|
          c.service_name = service
          c.add_span_processor(
            OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(JsonlExporter.new(path)),
          )
        end
        @tracer = OpenTelemetry.tracer_provider.tracer(service)
        @enabled = true
      rescue LoadError; @enabled = false
      rescue StandardError; @enabled = false
      end

      # The block runs exactly once whatever the tracer does: a span wraps
      # event_bus.publish and the audit append, so skipping it drops events and
      # re-running it after a raise appends twice.
      def self.span(name, attrs = {}, &block)
        return yield unless @enabled && @tracer

        @tracer.in_span(name, attributes: stringify(attrs), &block)
      end

      def self.stringify(hash)
        hash.each_with_object({}) { |(k, v), out| out[k.to_s] = v.to_s }
      end

      class JsonlExporter
        SUCCESS = 0
        FAILURE = 1

        def initialize(path, max_bytes: Master::Trace::Log::Event::MAX_BYTES)
          @path = path
          @max_bytes = max_bytes
        end

        def export(spans, timeout: nil)
          spans.each do |span|
            safe_name = Master::Trace::EventPrivacy.persisted("tool:after", name: span.name)
            safe_attributes = Master::Trace::EventPrivacy.persisted("tool:after", span.attributes)
            record = {
              kind: span.kind.to_s,
              start: span.start_timestamp,
              end: span.end_timestamp,
              dur_us: ((span.end_timestamp - span.start_timestamp) / 1000),
              attrs: safe_attributes,
              trace: span.hex_trace_id,
              span: span.hex_span_id,
            }.merge(safe_name)

            Master::Trace::Log.append_jsonl(
              @path,
              record,
              max_bytes: @max_bytes,
              mode: 0o600,
              sync: false,
            )
          end
          SUCCESS
        rescue StandardError
          FAILURE
        end

        def force_flush(timeout: nil) = SUCCESS
        def shutdown(timeout: nil) = SUCCESS
      end
    end
  end
end
