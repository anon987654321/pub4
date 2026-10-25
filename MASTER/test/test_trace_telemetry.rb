# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "tmpdir"

class TraceTelemetryExporterTest < Minitest::Test
  Span = Struct.new(
    :name, :kind, :start_timestamp, :end_timestamp, :attributes, :hex_trace_id, :hex_span_id,
    keyword_init: true,
  )

  def span(index)
    Span.new(
      name: "trace-#{index}",
      kind: :internal,
      start_timestamp: 1_000_000,
      end_timestamp: 1_250_000,
      attributes: { detail: "x" * 80 },
      hex_trace_id: format("%032x", index + 1),
      hex_span_id: format("%016x", index + 1),
    )
  end

  def test_exporter_rotates_trace_output_and_keeps_it_private
    Dir.mktmpdir("trace-exporter-") do |dir|
      path = File.join(dir, "traces.log")
      exporter = Master::Trace::Telemetry::JsonlExporter.new(path, max_bytes: 400)

      assert_equal Master::Trace::Telemetry::JsonlExporter::SUCCESS, exporter.export(8.times.map { |index| span(index) })
      assert_operator File.size(path), :<=, 400
      assert_operator File.size("#{path}.1"), :<=, 400
      File.readlines(path, chomp: true).each { |line| JSON.parse(line) }
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_equal 0o600, File.stat("#{path}.lock").mode & 0o777
    end
  end

  def test_exporter_reports_failure_for_a_record_over_its_cap
    Dir.mktmpdir("trace-exporter-oversize-") do |dir|
      path = File.join(dir, "traces.log")
      exporter = Master::Trace::Telemetry::JsonlExporter.new(path, max_bytes: 40)

      assert_equal Master::Trace::Telemetry::JsonlExporter::FAILURE, exporter.export([span(1)])
      refute File.exist?(path)
    end
  end
end
