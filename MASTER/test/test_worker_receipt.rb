# frozen_string_literal: true

require_relative "test_helper"
require "json"

class TestWorkerReceipt < Minitest::Test
  Receipt = Master::Trace::WorkerReceipt

  class DownBus
    def publish_required(*) = raise(IOError, "required event persistence failed")
    def publish(*) = nil
  end

  def setup
    @dir = Dir.mktmpdir("worker-receipt-")
    @bus = Master::Trace::EventBus.new(
      event_log: Master::Trace::Log::Event.new(root: @dir),
      evidence_log: Master::Trace::Log::Evidence.new(root: @dir)
    )
  end

  def teardown = FileUtils.rm_rf(@dir)

  def evidence
    path = File.join(@dir, "runtime", "events", "evidence.jsonl")
    File.file?(path) ? File.readlines(path).map { |line| JSON.parse(line) } : []
  end

  def test_work_lands_between_a_durable_before_and_an_after
    result = Receipt.around(@bus, worker: "heartbeat", job: "canary") { Master::Result.ok(:done) }

    assert result.ok?
    rows = evidence
    assert_equal %w[worker:before worker:after], rows.map { |row| row["event"] }
    assert_equal rows.first.dig("payload", "invocation_id"), rows.last.dig("payload", "invocation_id")
    assert_equal "success", rows.last.dig("payload", "status")
    assert_equal "canary", rows.first.dig("payload", "job")
  end

  def test_no_durable_before_means_the_work_never_starts
    ran = false

    assert_raises(IOError) { Receipt.around(DownBus.new, worker: "heartbeat", job: "canary") { ran = true } }
    refute ran
  end

  def test_work_that_raises_is_recorded_as_an_error
    assert_raises(RuntimeError) { Receipt.around(@bus, worker: "task_steward", job: "mission m") { raise "provider down" } }

    assert_equal "error", evidence.last.dig("payload", "status")
  end

  def test_work_past_its_deadline_is_cut_and_recorded_as_a_timeout
    assert_raises(Timeout::Error) { Receipt.around(@bus, worker: "heartbeat", job: "canary", deadline_s: 0.05) { sleep 2 } }

    assert_equal "timeout", evidence.last.dig("payload", "status")
  end

  def test_a_job_ends_by_its_next_turn_or_the_cap
    heartbeat = Master::Fix::Heartbeat.new(root: @dir, event_bus: @bus)

    assert_equal 120, heartbeat.send(:job_deadline, { "interval_seconds" => 120 })
    assert_equal 300, heartbeat.send(:job_deadline, { "interval_seconds" => 3600 })
    assert_equal 30, heartbeat.send(:job_deadline, { "interval_seconds" => 3600, "timeout_seconds" => 30 })
  end

  def test_heartbeat_jobs_carry_receipts
    Master::Fix::Heartbeat.new(root: @dir, event_bus: @bus).send(:execute_job, { "name" => "self_test", "action" => "self_test" })

    assert_equal %w[worker:before worker:after], evidence.map { |row| row["event"] }
    assert_equal "heartbeat", evidence.first.dig("payload", "worker")
  end
end
