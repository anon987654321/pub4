# frozen_string_literal: true

require_relative "test_helper"

# Ledger::Swallow subscribes to swallow:error events and tallies them per
# context, flushing a JSONL snapshot every SNAPSHOT_EVERY swallows.
class TestSwallowLedger < Minitest::Test
  # Minimal in-memory bus matching EventBus#subscribe / #publish.
  class FakeBus
    def initialize = @subs = {}
    def subscribe(pattern, &handler) = (@subs[pattern] ||= []) << handler
    def publish(event, payload = {}) = (@subs[event] || []).each { |h| h.call(payload) }
  end

  def setup
    @root   = Dir.mktmpdir("swallow_ledger_test")
    @bus    = FakeBus.new
    @ledger = Master::Trace::Ledger::Swallow.new(event_bus: @bus, root: @root).attach
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && Dir.exist?(@root)
  end

  def test_tallies_swallows_by_context
    3.times { @bus.publish("swallow:error", context: "cli.diff_stat") }
    2.times { @bus.publish("swallow:error", context: "renderer.git_rev") }

    snap = @ledger.snapshot
    assert_equal 3, snap["cli.diff_stat"]
    assert_equal 2, snap["renderer.git_rev"]
    assert_equal 5, @ledger.total
  end

  def test_missing_context_falls_back_to_unknown
    @bus.publish("swallow:error", {})
    assert_equal 1, @ledger.snapshot["unknown"]
  end

  def test_accepts_string_keyed_payload
    @bus.publish("swallow:error", "context" => "memory.load_store")
    assert_equal 1, @ledger.snapshot["memory.load_store"]
  end

  def test_flushes_snapshot_every_50_swallows
    ledger_file = File.join(@root, "runtime", "swallow_ledger.jsonl")
    49.times { @bus.publish("swallow:error", context: "x") }
    refute File.exist?(ledger_file), "no flush before the 50th swallow"

    @bus.publish("swallow:error", context: "x")
    assert File.exist?(ledger_file), "flush on the 50th swallow"

    record = JSON.parse(File.readlines(ledger_file).last)
    assert_equal 50, record["total"]
    assert_equal 50, record["counts"]["x"]
  end

  def test_attach_without_bus_is_safe
    ledger = Master::Trace::Ledger::Swallow.new(event_bus: nil, root: @root).attach
    assert_equal 0, ledger.total
  end
end
