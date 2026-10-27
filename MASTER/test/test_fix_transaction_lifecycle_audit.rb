# frozen_string_literal: true

require "tmpdir"
require "json"
require_relative "test_helper"
require_relative "../lib/fix/transaction"

class TestFixTransactionLifecycleAudit < Minitest::Test
  class StrictAuditBus
    attr_reader :events
    attr_accessor :failure

    def initialize
      @events = []
    end

    def publish_required(event, payload = {})
      raise IOError, "simulated audit failure" if event == failure

      @events << [event, payload]
      self
    end

    def publish(event, **payload)
      @events << [event, payload]
      self
    end
  end

  def test_transaction_lifecycle_events_are_paired_and_do_not_persist_paths
    Dir.mktmpdir do |dir|
      path = File.join(dir, "private-note.txt")
      File.write(path, "before")
      bus = StrictAuditBus.new

      tx = Master::Fix::Transaction.new(root: dir, paths: ["private-note.txt"], id: "audit-safe", bus:).begin!
      lifecycle = bus.events.select { |name, _payload| name.start_with?("fix:transaction_lifecycle:") }

      assert_equal %w[fix:transaction_lifecycle:before fix:transaction_lifecycle:after], lifecycle.map(&:first)
      assert_equal lifecycle.first.last.fetch(:audit_id), lifecycle.last.last.fetch(:audit_id)
      assert_equal "begin", lifecycle.first.last.fetch(:operation)
      assert_equal "ok", lifecycle.last.last.fetch(:status)
      refute_includes bus.events.inspect, "private-note.txt"
      assert tx.rollback!.ok?
    end
  end

  def test_missing_after_audit_record_blocks_transaction_recovery
    Dir.mktmpdir do |dir|
      path = File.join(dir, "note.txt")
      File.write(path, "before")
      bus = StrictAuditBus.new
      bus.failure = "fix:transaction_lifecycle:after"
      tx = Master::Fix::Transaction.new(root: dir, paths: ["note.txt"], id: "audit-failure", bus:)

      assert_raises(IOError) { tx.begin! }

      marker = File.join(dir, ".master", "fix_transactions", ".pending-audit-failure")
      manifest = File.join(dir, ".master", "fix_transactions", "audit-failure", "manifest.json")
      assert File.file?(marker), "the incomplete lifecycle must be durable"
      assert File.file?(manifest), "retain the transaction manifest for diagnosis"
      assert_equal "trace_failed", JSON.parse(File.read(manifest)).fetch("state")
      assert_equal "before", File.read(path)

      recovered = Master::Fix::Transaction::Recovery.recover!(root: dir, id: "audit-failure")

      refute recovered.ok?
      assert_match(/lifecycle audit is incomplete/, recovered.message)
      assert File.file?(marker)
      assert_equal "before", File.read(path), "recovery must not silently mutate an incompletely audited transaction"
    end
  end
end
