# frozen_string_literal: true

require_relative "test_helper"

# Four trace pieces with no test of their own: Telemetry wraps the bus and the
# audit log in spans, Recorder keeps the last turn for /why, Logging feeds
# dmesg from every event, and Triggers runs named handlers without letting one
# failure stop the rest.
class TestTraceSupport < Minitest::Test
  def test_verbose_is_the_default_operator_mode
    previous = ENV["MASTER_DMESG"]
    previous_quiet = ENV["MASTER_QUIET"]
    ENV.delete("MASTER_DMESG")
    ENV.delete("MASTER_QUIET")
    Master::Trace::Dmesg.reload!
    assert_equal "verbose", Master::Trace::Dmesg.verbosity
  ensure
    previous.nil? ? ENV.delete("MASTER_DMESG") : ENV["MASTER_DMESG"] = previous
    previous_quiet.nil? ? ENV.delete("MASTER_QUIET") : ENV["MASTER_QUIET"] = previous_quiet
    Master::Trace::Dmesg.reload!
  end

  # A chat turn that set off a background self-scan printed 2,657 per-file
  # scan and hook lines ahead of a one-line reply. Verbose shows the work;
  # only trace shows each file of it.
  def test_verbose_hides_per_file_churn_that_trace_shows
    console = Master::Trace::Dmesg::Console.new
    churn = [{ event: "scan:pass", path: "lib/a.rb" }, { event: "hook:on_violation_found", path: "lib/a.rb", count: 2 },
             { event: "cognition:tick" }]

    verbose = Master::Trace::Dmesg.with_verbosity("verbose") { churn.flat_map { |event| console.lines(**event) } }
    traced = Master::Trace::Dmesg.with_verbosity("trace") { churn.flat_map { |event| console.lines(**event) } }

    assert_empty verbose
    assert_equal 3, traced.size
  end

  def test_trace_includes_redacted_payload_context
    console = Master::Trace::Dmesg::Console.new
    lines = Master::Trace::Dmesg.with_verbosity("trace") do
      console.lines(event: "fix_loop:scan_progress", file: "lib/a.rb", count: 2,
                    api_key: "sk-secret-value")
    end

    assert_equal 1, lines.size
    assert_includes lines.first, "fix0: scan_progress"
    assert_includes lines.first, "lib/a.rb"
    refute_includes lines.first, "sk-secret-value"
  end
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

  # Verbose is the operator default: every model send/outcome is visible.
  def test_verbose_model_calls_are_visible_by_default
    console = Master::Trace::Dmesg::Console.new
    Fiber[:master_unit] = "scan0"
    printed = 8.times.flat_map do |i|
      console.lines(event: "llm:send", model: i.even? ? "claude-cli:claude-opus-4-8" : "ollama:gemma3:4b") +
        console.lines(event: "llm:provider_outcome", model: "x", status: :success, latency_ms: 10)
    end

    assert_equal 16, printed.size
    assert_equal "llm0 at scan0: claude-cli:claude-opus-4-8", printed.first
    assert_match(/llm0: .*0\.0s/, printed[1])
  ensure
    Fiber[:master_unit] = nil
  end

  def test_normal_model_calls_roll_up_after_the_burst
    Master::Trace::Dmesg.with_verbosity("normal") do
      console = Master::Trace::Dmesg::Console.new
      Fiber[:master_unit] = "scan0"
      printed = 60.times.flat_map do |i|
        console.lines(event: "llm:send", model: i.even? ? "claude-cli:claude-opus-4-8" : "ollama:gemma3:4b") +
          console.lines(event: "llm:provider_outcome", model: "x", status: :success, latency_ms: 10)
      end

      assert_operator printed.size, :<, 12, printed.join("\n")
      assert(printed.any? { |line| line.match?(/\Ascan0: \d+ model calls, 2 lanes\z/) },
           "no rollup line: #{printed.join(" | ")}")
    ensure
      Fiber[:master_unit] = nil
    end
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

  # The fallback format is for an event the console gives no line, which is
  # normal mode; under verbose, the default, every event has a console line.
  def test_dmesg_finding_filters_accept_ansi_and_verdict_lines
    text = "\e[31mfix0: MASTER/lib/example.rb:12: missing gate\e[0m\r\n"
    assert_equal ["fix0: MASTER/lib/example.rb:12: missing gate"], Master::Trace::Dmesg.findings(text)
    assert_equal "plain line", Master::Trace::Dmesg.plain("plain line\r")
  end

  def test_logging_formats_tool_events_and_redacts_details
    bus = Bus.new
    logging = Master::Trace::Logging.new(ring_buffer: [], event_bus: bus)
    Master::Trace::Dmesg.with_verbosity("normal") do
      bus.emit("**", { event: "tool:write", path: "lib/a.rb", bytes: 12, ts: 1 })
      bus.emit("**", { event: "boot", ts: 1 })
      bus.emit("**", { event: "llm:call", api_key: "sk-or-v1-0123456789abcdef0123456789abcdef", ts: 1 })
    end

    lines = logging.dmesg.lines.map(&:chomp)
    assert_equal "tool: write lib/a.rb 12B", lines[0]
    assert_equal "boot0: ready", lines[1]
    refute_includes lines[2], "0123456789abcdef0123456789abcdef"
  end

  # The coding loop prints like the kernel: a parent attaches once, each effect
  # is a numbered unit under it, and a failure reports its last line.
  FOLD_EVENTS = [
    { event: "fold:risk", risk: :low },
    { event: "core:reason", why: "read the logger before describing it" },
    { event: "core:turn", verb: :read, subject: "lib/trace/logging.rb", ok: true, detail: "a\nb\n" },
    { event: "core:turn", verb: :exec, subject: "rake test", ok: false, detail: "run\n1 failure\n" },
    { event: "core:turn", verb: :read, subject: "lib/trace/dmesg.rb", ok: true, detail: "c\n" },
    { event: "core:turn", turn: 3, verb: :done, subject: "both described", ok: true, detail: "done" },
  ].freeze

  def test_console_renders_a_fold_turn_as_dmesg_units
    console = Master::Trace::Dmesg::Console.new
    lines = FOLD_EVENTS.flat_map { |payload| console.lines(payload) }

    assert_equal [
      "fold0 at master0: risk low",
      "fold0: read the logger before describing it",
      "read0 at fold0: lib/trace/logging.rb",
      "read0: 4 bytes, 2 lines",
      "exec0 at fold0: rake test",
      "exec0: 1 failure",
      "read1 at fold0: lib/trace/dmesg.rb",
      "read1: 2 bytes, 1 line",
      "fold0: done, 4 turns",
    ], lines
  end

  def test_console_reports_a_failed_model_call_and_a_failed_tool
    console = Master::Trace::Dmesg::Console.new
    lines = [
      { event: "llm:send", model: "nvidia/nemotron-3-super-120b-a12b:free" },
      { event: "llm:provider_outcome", model: "nvidia/nemotron-3-super-120b-a12b:free", status: :provider_error,
        error: "Upstream error from Nvidia: Service temporarily overloaded" },
      { event: "tool:call", tool: "read_file", subject: "missing.rb" },
      { event: "tool:return", tool: "read_file", ok: false, error: "no such file" },
    ].flat_map { |payload| console.lines(payload) }

    assert_equal [
      "llm0 at master0: nvidia/nemotron-3-super-120b-a12b",
      "llm0: provider_error, Upstream error from Nvidia: Service temporarily overloaded",
      "io0 at master0: files and commands",
      "read0 at io0: missing.rb",
      "read0: no such file",
    ], lines
  end

  # A scan's model calls and the fold's must not both read "at master0".
  def test_a_model_call_attaches_to_the_work_that_asked_for_it
    console = Master::Trace::Dmesg::Console.new
    inside = Master::Trace::Dmesg.under("scan0") { Thread.new { console.lines(event: "llm:send", model: "m") }.value }
    outside = console.lines(event: "llm:send", model: "m")

    assert_equal ["llm0 at scan0: m"], inside
    assert_equal ["llm1 at master0: m"], outside
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
