# frozen_string_literal: true

require_relative "test_helper"
require "digest"
require "fileutils"
require "json"
require_relative "../lib/io/llm"
require_relative "../lib/io/mcp_coordinator"

class ToolObserverTest < Minitest::Test
  class StrictBus
    attr_reader :required_events, :events
    attr_accessor :fail_event

    def initialize
      @required_events = []
      @events = []
      @fail_event = nil
    end

    def publish_required(event, payload = {})
      raise IOError, "persistence unavailable" if @fail_event == event

      @required_events << [event, payload]
      self
    end

    def publish(event, payload = {})
      @events << [event, payload]
      self
    end
  end

  class FakeTool
    NAME = "fake_tool"
    TIER = :guarded

    attr_reader :calls

    def initialize(bus, raises: false, result: nil)
      @bus = bus
      @raises = raises
      @result = result
      @calls = []
    end

    def call(**args)
      @calls << args
      unless @bus.required_events.any? { |event, _| event == Master::Trace::ToolObserver::BEFORE_EVENT }
        raise "tool entered without its durable before receipt"
      end
      raise "remote write response was lost" if @raises

      @result || Master::Result.ok("completed")
    end
  end

  class Forwarder
    include Master::Io::LLM::ToolForwarding

    def invoke(**args) = forward(**args)
  end

  def setup
    Fiber[:master_tool_streak] = nil
    Fiber[:master_tree_seen] = true
    @dir = Dir.mktmpdir("master-tool-observer-")
    @bus = Master::Trace::EventBus.new(
      event_log: Master::Trace::Log::Event.new(root: @dir),
      evidence_log: Master::Trace::Log::Evidence.new(root: @dir)
    )
    @observer = Master::Trace::ToolObserver.new(bus: @bus)
  end

  def teardown
    Fiber[:master_tool_streak] = nil
    Fiber[:master_tree_seen] = nil
    FileUtils.rm_rf(@dir)
  end

  def test_durable_receipts_pair_and_keep_arguments_private_in_activity_and_evidence
    args = { path: "/private/source.rb", content: "the source contains a private note" }
    identity = @observer.before(tool: "write_file", tier: "guarded", args:, invocation_id: "call-receipt-1")
    @observer.after(
      identity:, tool: "write_file", tier: "guarded", args:, status: "success",
      elapsed_ms: 11, result_bytes: 9
    )

    digest_input = JSON.generate({ "content" => args[:content], "path" => args[:path] })
    digest = Digest::SHA256.hexdigest(digest_input)
    activity = File.read(File.join(@dir, "runtime/events/activity.jsonl"))
    evidence = File.read(File.join(@dir, "runtime/events/evidence.jsonl"))

    [activity, evidence].each do |contents|
      refute_includes contents, args[:path]
      refute_includes contents, args[:content]
      assert_includes contents, digest
      assert_includes contents, "tool:execution:before"
      assert_includes contents, "tool:execution:after"
    end

    rows = File.readlines(File.join(@dir, "runtime/events/evidence.jsonl"), chomp: true).map { |line| JSON.parse(line) }
    rows = rows.select { |row| row.dig("payload", "invocation_id") == identity.invocation_id }
    assert_equal %w[tool:execution:before tool:execution:after], rows.map { |row| row["event"] }
    assert_nil rows.first.dig("payload", "status")
    assert_equal "success", rows.last.dig("payload", "status")
  end

  def test_after_without_a_before_receipt_is_rejected
    error = assert_raises(ArgumentError) do
      @observer.after(
        invocation_id: "missing-before", tool: "read_file", tier: "guarded",
        args: { path: "README.md" }, status: "success", elapsed_ms: 1
      )
    end
    assert_match(/matching before-event/, error.message)
  end

  def test_mismatched_after_receipt_quarantines_original_arguments_until_reconciled
    original = { path: "private.txt", content: "original" }
    identity = @observer.before(tool: "write_file", tier: "guarded", args: original, invocation_id: "mismatch-1")

    error = assert_raises(Master::Trace::ToolObserver::UnknownOutcome) do
      @observer.after(
        identity:, tool: "write_file", tier: "guarded",
        args: { path: "other.txt", content: "different" },
        status: "success", elapsed_ms: 2
      )
    end
    assert_match(/reconcile before retrying/, error.message)

    blocked = assert_raises(Master::Trace::ToolObserver::UnknownOutcome) do
      @observer.before(tool: "write_file", tier: "guarded", args: original, invocation_id: "mismatch-2")
    end
    assert_equal identity.invocation_id, blocked.invocation_id

    @observer.reconcile!(
      tool: "write_file", args: original, evidence_ref: "verify:artifact-1",
      outcome: "confirmed_failure", invocation_id: identity.invocation_id
    )
    resumed = @observer.before(tool: "write_file", tier: "guarded", args: original, invocation_id: "mismatch-3")
    assert_equal "mismatch-3", resumed.invocation_id
  end

  def test_after_persistence_failure_blocks_replay_until_operator_reconciliation
    bus = StrictBus.new
    observer = Master::Trace::ToolObserver.new(bus:)
    args = { command: "mutating operation" }
    observer.before(tool: "fake_tool", tier: "guarded", args:, invocation_id: "persist-fail-1")
    bus.fail_event = Master::Trace::ToolObserver::AFTER_EVENT

    assert_raises(Master::Trace::ToolObserver::UnknownOutcome) do
      observer.after(
        invocation_id: "persist-fail-1", tool: "fake_tool", tier: "guarded", args:,
        status: "success", elapsed_ms: 1
      )
    end
    bus.fail_event = nil

    assert_raises(Master::Trace::ToolObserver::UnknownOutcome) do
      observer.before(tool: "fake_tool", tier: "guarded", args:, invocation_id: "persist-fail-2")
    end
    observer.reconcile!(
      tool: "fake_tool", args:, evidence_ref: "ticket:verify-22", outcome: "safe_to_retry",
      invocation_id: "persist-fail-1"
    )
    assert_equal "persist-fail-3",
                 observer.before(tool: "fake_tool", tier: "guarded", args:, invocation_id: "persist-fail-3").invocation_id
  end

  def test_before_receipt_failure_means_tool_is_not_entered
    bus = StrictBus.new
    bus.fail_event = Master::Trace::ToolObserver::BEFORE_EVENT
    observer = Master::Trace::ToolObserver.new(bus:)
    tool = FakeTool.new(bus)
    forwarder = Forwarder.new(tool, bus:, tool_observer: observer)

    reply = forwarder.invoke(path: "private.txt")

    assert_match(/was not executed/, reply)
    assert_empty tool.calls
  ensure
    Fiber[:master_tree_seen] = nil
    Fiber[:master_tool_streak] = nil
  end

  def test_unknown_after_receipt_quarantines_model_tool_replay
    bus = StrictBus.new
    observer = Master::Trace::ToolObserver.new(bus:)
    tool = FakeTool.new(bus)
    forwarder = Forwarder.new(tool, bus:, tool_observer: observer)
    args = { command: "write a value" }
    bus.fail_event = Master::Trace::ToolObserver::AFTER_EVENT

    first = forwarder.invoke(**args)
    second = forwarder.invoke(**args)

    assert_match(/verify the current state and reconcile/, first)
    assert_match(/outcome is unresolved/, second)
    assert_equal 1, tool.calls.length
  ensure
    Fiber[:master_tree_seen] = nil
    Fiber[:master_tool_streak] = nil
  end

  def test_uncertain_tool_failure_outcome_quarantines_replay
    bus = StrictBus.new
    observer = Master::Trace::ToolObserver.new(bus:)
    failure = Master::Result.err("remote write may have partially succeeded", category: :infrastructure)
    tool = FakeTool.new(bus, result: failure)
    forwarder = Forwarder.new(tool, bus:, tool_observer: observer)
    args = { command: "write a value" }

    first = forwarder.invoke(**args)
    second = forwarder.invoke(**args)

    assert_match(/verify the current state and reconcile/, first)
    assert_match(/outcome is unresolved/, second)
    assert_equal 1, tool.calls.length
    after = bus.required_events.reverse.find { |event, _| event == Master::Trace::ToolObserver::AFTER_EVENT }
    assert_equal "unknown_outcome", after.last[:status]
  ensure
    Fiber[:master_tree_seen] = nil
    Fiber[:master_tool_streak] = nil
  end

  def test_mcp_execution_uses_the_same_receipt_boundary
    bus = StrictBus.new
    observer = Master::Trace::ToolObserver.new(bus:)
    calls = []
    client = Object.new
    client.define_singleton_method(:call_tool) do |tool:, arguments:|
      calls << [tool, arguments]
      { "result" => { "content" => [{ "text" => "done" }] } }
    end
    mcp_tool = Struct.new(:name, :description).new("mutate", "Writes a remote value")
    wrapper = Master::Io::McpToolWrapper.new(
      name: "test_server", client:, tool: mcp_tool, governor: nil,
      event_bus: bus, tool_observer: observer, tier: :guarded
    )

    output = wrapper.execute(secret: "remote private input")

    refute_empty output
    assert_equal 1, calls.length
    assert_equal [Master::Trace::ToolObserver::BEFORE_EVENT, Master::Trace::ToolObserver::AFTER_EVENT],
                 bus.required_events.map(&:first)
    refute_includes JSON.generate(bus.required_events), "remote private input"
  end

  def receipt(id, args, pid:)
    document = JSON.generate(args.transform_keys(&:to_s).sort.to_h)
    @bus.publish_required(
      Master::Trace::ToolObserver::BEFORE_EVENT,
      { schema_version: 1, invocation_id: id, tool: "write_file", tier: "guarded",
        arguments_digest: Digest::SHA256.hexdigest(document), arguments_bytes: document.bytesize, pid: }
    )
  end

  def dead_pid
    pid = Process.spawn(RbConfig.ruby, "-e", "")
    Process.wait(pid)
    pid
  end

  def restarted = Master::Trace::ToolObserver.new(bus: @bus)

  # A process that died between its before- and after-receipt may have written;
  # the next process must not repeat the call blind.
  def test_a_crash_mid_call_stays_quarantined_after_restart
    args = { path: "ledger.txt" }
    receipt("crash-1", args, pid: dead_pid)

    blocked = assert_raises(Master::Trace::ToolObserver::UnknownOutcome) do
      restarted.before(tool: "write_file", tier: "guarded", args:, invocation_id: "crash-2")
    end
    assert_equal "crash-1", blocked.invocation_id
  end

  def test_a_call_still_running_in_another_process_is_not_quarantined
    args = { path: "ledger.txt" }
    receipt("live-1", args, pid: Process.pid)

    assert_equal "live-2", restarted.before(tool: "write_file", tier: "guarded", args:, invocation_id: "live-2").invocation_id
  end

  def test_an_unknown_outcome_survives_restart_until_another_observer_reconciles_it
    args = { path: "remote.txt" }
    identity = @observer.before(tool: "write_file", tier: "guarded", args:, invocation_id: "unknown-1")
    @observer.after(identity:, tool: "write_file", tier: "guarded", args:, status: "unknown_outcome", elapsed_ms: 3)
    survivor = restarted

    assert_equal ["unknown-1"], survivor.unresolved.map(&:invocation_id)
    restarted.reconcile_invocation!(invocation_id: "unknown-1", outcome: "still_unknown", evidence_ref: "verify:one")
    assert_raises(Master::Trace::ToolObserver::UnknownOutcome) do
      survivor.before(tool: "write_file", tier: "guarded", args:, invocation_id: "unknown-2")
    end

    restarted.reconcile_invocation!(invocation_id: "unknown-1", outcome: "confirmed_failure", evidence_ref: "verify:two")
    assert_equal "unknown-3", survivor.before(tool: "write_file", tier: "guarded", args:, invocation_id: "unknown-3").invocation_id
    assert_empty restarted.unresolved
  end

  # An after-receipt that never reached the log leaves only the in-memory
  # quarantine; no durable record may lift it but a reconciliation.
  def test_an_unpersisted_after_receipt_is_not_released_by_the_log
    bus = StrictBus.new
    observer = Master::Trace::ToolObserver.new(bus:)
    def bus.receipt_history = []
    args = { command: "mutate" }
    observer.before(tool: "fake_tool", tier: "guarded", args:, invocation_id: "memory-1")
    bus.fail_event = Master::Trace::ToolObserver::AFTER_EVENT
    assert_raises(Master::Trace::ToolObserver::UnknownOutcome) do
      observer.after(invocation_id: "memory-1", tool: "fake_tool", tier: "guarded", args:, status: "success", elapsed_ms: 1)
    end
    bus.fail_event = nil

    assert_raises(Master::Trace::ToolObserver::UnknownOutcome) do
      observer.before(tool: "fake_tool", tier: "guarded", args:, invocation_id: "memory-2")
    end
  end

  def test_doctor_tools_lists_and_reconciles_unknown_outcomes
    receipt("doctor-1", { path: "ledger.txt" }, pid: dead_pid)
    doctor = ->(args) { Master::CLI::CommandRegistry.dispatch_doctor(@dir, ctx: { args: "tools #{args}" }) }

    assert_match(/tools0: doctor-1 write_file guarded unresolved/, doctor.(""))
    assert_equal "tools0: write_file doctor-1 reconciled safe_to_retry", doctor.("reconcile doctor-1 safe_to_retry verify:disk")
    assert_equal "tools0: no unresolved tool outcome", doctor.("")
    assert_match(/no unresolved invocation has id doctor-1/, doctor.("reconcile doctor-1 safe_to_retry verify:disk"))
  end
end
