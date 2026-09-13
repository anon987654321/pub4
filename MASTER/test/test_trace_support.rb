# frozen_string_literal: true

require_relative "test_helper"

# Four trace pieces with no test of their own: Telemetry wraps the bus and the
# audit log in spans, Recorder keeps the last turn for /why, Logging feeds
# dmesg from every event, and Triggers runs named handlers without letting one
# failure stop the rest.
class TestTraceSupport < Minitest::Test
  class Bus
    attr_reader :published

    def initialize
      @handlers = Hash.new { |h, k| h[k] = [] }
      @published = []
    end

    def subscribe(pattern, &block) = @handlers[pattern] << block
    def publish(event, **payload) = @published << [event, payload]

    def emit(pattern, payload) = @handlers[pattern].each { |h| h.call(payload) }
  end

  def test_a_span_runs_its_block_once_when_tracing_is_off
    runs = 0
    value = Master::Trace::Telemetry.span("x") { runs += 1 }

    assert_equal 1, value
    assert_equal 1, runs
  end

  def test_a_raising_block_raises_once_and_is_not_run_again
    runs = 0
    assert_raises(RuntimeError) do
      Master::Trace::Telemetry.span("x") do
        runs += 1
        raise "append failed"
      end
    end
    assert_equal 1, runs
  end

  class Tracer
    attr_reader :spans

    def initialize = @spans = []

    def in_span(name, attributes:)
      @spans << [name, attributes]
      yield
    end
  end

  def test_an_enabled_tracer_wraps_the_block_with_stringified_attributes
    tracer = Tracer.new
    telemetry = Master::Trace::Telemetry
    telemetry.instance_variable_set(:@enabled, true)
    telemetry.instance_variable_set(:@tracer, tracer)

    assert_equal :done, telemetry.span("bus.publish", n: 3) { :done }
    assert_equal [["bus.publish", { "n" => "3" }]], tracer.spans
  ensure
    telemetry.instance_variable_set(:@enabled, false)
    telemetry.instance_variable_set(:@tracer, nil)
  end

  def test_the_recorder_keeps_a_turn_and_reads_it_back_after_a_restart
    root = Dir.mktmpdir("recorder_")
    bus = Bus.new
    recorder = Master::Trace::Recorder.new(root:, event_bus: bus)
    bus.emit("gateway:*", { event: "gateway:turn_start", turn_id: "t1", channel: :cli, message: "hi", ts: 100 })
    bus.emit("pipeline:*", { event: "pipeline:stage", stage: "render", ts: 130 })
    bus.emit("gateway:*", { event: "gateway:turn_done", ts: 150 })

    assert_match(/\+   30ms  pipeline:stage  \{stage: "render"\}/, recorder.pretty_last)
    fresh = Master::Trace::Recorder.new(root:, event_bus: Bus.new)
    assert_match(/turn t1 .*channel=cli/, fresh.pretty_last)
  ensure
    FileUtils.rm_rf(root)
  end

  def test_events_outside_a_turn_are_not_recorded
    root = Dir.mktmpdir("recorder_")
    bus = Bus.new
    recorder = Master::Trace::Recorder.new(root:, event_bus: bus)
    bus.emit("pipeline:*", { event: "pipeline:stage", ts: 1 })

    assert_equal "no trace recorded yet", recorder.pretty_last
  ensure
    FileUtils.rm_rf(root)
  end

  def test_logging_formats_tool_events_and_redacts_details
    bus = Bus.new
    logging = Master::Trace::Logging.new(ring_buffer: [], event_bus: bus)
    bus.emit("**", { event: "tool:write", path: "lib/a.rb", bytes: 12, ts: 1 })
    bus.emit("**", { event: "boot", ts: 1 })
    bus.emit("**", { event: "llm:call", api_key: "sk-or-v1-0123456789abcdef0123456789abcdef", ts: 1 })

    lines = logging.dmesg.lines.map(&:chomp)
    assert_equal "tool: write lib/a.rb 12B", lines[0]
    assert_equal "boot: ready", lines[1]
    refute_includes lines[2], "0123456789abcdef0123456789abcdef"
  end

  def test_triggers_isolate_a_failing_handler
    bus = Bus.new
    triggers = Master::Trace::Triggers.new(event_bus: bus).install_defaults!
    triggers.register(:after_scan) { raise "broken handler" }
    triggers.fire(:after_scan, violations: 2)
    triggers.fire(:after_scan, violations: 0)

    assert_equal 2, bus.published.count { |name, _| name == "triggers:handler_error" }
    assert_equal [["triggers:violations_found", { count: 2 }]], bus.published.select { |name, _| name.end_with?("found") }
    assert_includes triggers.list, "after_scan: 2 handler(s)"
  end
end
