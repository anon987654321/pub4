# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "json"
require "fileutils"
require "digest"

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

  def test_reflexion_event_bus_uses_fingerprints_not_raw_failure_details
    events = []
    bus = FakeBus.new
    bus.subscribe("reflexion:recorded") { |payload| events << payload }
    Master::Trace::Ledger::Reflexion.new(event_bus: bus, root: @dir).attach
    private_reason = "authorization denied: Bearer #{'S' * 40} at private/customer-account.csv"
    private_file = "customer-account.csv"

    bus.publish("fix_loop:commit_error", reason: private_reason, files: ["lib/#{private_file}"])

    event = events.fetch(0)
    assert_equal Digest::SHA256.hexdigest(private_reason), event.fetch(:reason_digest)
    assert_equal private_reason.bytesize, event.fetch(:reason_bytes)
    assert_equal 1, event.fetch(:files_count)
    assert_equal Digest::SHA256.hexdigest(private_file), event.fetch(:files_digest)
    refute_includes events.inspect, private_reason
    refute_includes events.inspect, private_file

    persisted = File.read(File.join(@dir, "runtime", "reflexions.ndjson"))
    refute_includes persisted, 'Bearer ' + ('S' * 40)
    assert_includes persisted, "[REDACTED]"
  end

  def test_caps_reflection_history
    bus = FakeBus.new
    Master::Trace::Ledger::Reflexion.new(event_bus: bus, root: @dir).attach
    60.times { |i| bus.publish("fix_loop:commit_blocked", reason: "rubocop", files: ["lib/f#{i}.rb"]) }

    path = File.join(@dir, "runtime", "reflexions.ndjson")
    assert_operator File.readlines(path).size, :<=, 50
  end

  def test_concurrent_appends_keep_fifty_unique_private_records
    bus = FakeBus.new
    bus.subscribe("reflexion:recorded") {}
    Master::Trace::Ledger::Reflexion.new(event_bus: bus, root: @dir).attach

    threads = 8.times.map do |worker|
      Thread.new do
        25.times do |index|
          bus.publish(
            "fix_loop:commit_blocked",
            reason: "worker-#{worker}-entry-#{index}",
            files: ["lib/#{worker}-#{index}.rb"],
          )
        end
      end
    end
    threads.each(&:value)

    path = File.join(@dir, "runtime", "reflexions.ndjson")
    lines = File.readlines(path, chomp: true)
    records = lines.map { |line| JSON.parse(line) }
    reasons = records.map { |record| record.fetch("reason") }

    assert_equal 50, records.size
    assert_equal 50, reasons.uniq.size, "concurrent commits must not overwrite a peer's retained row"
    assert_equal 0o600, File.stat(path).mode & 0o777
    assert File.file?("#{path}.lock")
    assert_equal 0o600, File.stat("#{path}.lock").mode & 0o777
  end
end
