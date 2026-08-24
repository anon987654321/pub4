# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"

# Reflexion episodic memory: blocked/failed commits become reflections that guide retries.
class TestReflexionLedger < Minitest::Test
  class FakeBus
    def initialize
      @subs = Hash.new { |hash, key| hash[key] = [] }
    end

    def subscribe(name, &blk)
      @subs[name] << blk
    end

    def publish(name, payload = {})
      @subs[name].each { |blk| blk.call(payload) }
    end
  end

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  def test_records_blocked_commit_as_reflection
    bus = FakeBus.new
    Master::Trace::Ledger::Reflexion.new(event_bus: bus, root: @dir).attach
    bus.publish("fix_loop:commit_blocked", reason: "syntax", files: ["lib/a.rb"])

    reflections = Master::Trace::Ledger::Reflexion.new(event_bus: bus, root: @dir).recent
    assert_equal 1, reflections.size
    assert_includes reflections.first, "syntax"
    assert_includes reflections.first, "a.rb"
  end

  def test_caps_reflection_history
    bus = FakeBus.new
    Master::Trace::Ledger::Reflexion.new(event_bus: bus, root: @dir).attach
    60.times { |i| bus.publish("fix_loop:commit_blocked", reason: "rubocop", files: ["lib/f#{i}.rb"]) }

    path = File.join(@dir, "runtime", "reflexions.ndjson")
    assert_operator File.readlines(path).size, :<=, 50
  end
end
