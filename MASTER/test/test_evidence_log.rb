# frozen_string_literal: true

require_relative "test_helper"

class TestEvidenceLog < Minitest::Test
  include Master

  def setup
    @dir = Dir.mktmpdir
    @events_dir = File.join(@dir, "runtime", "events")
    FileUtils.mkdir_p(@events_dir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_operational_events_match_prefixes
    log = Trace::Log::Evidence.new(root: @dir)
    assert log.operational?("ops:commit")
    assert log.operational?("pipeline:rollback")
    assert log.operational?("resync:reset")
    assert log.operational?("deploy:restart")
    refute log.operational?("scan:complete")
  end

  def test_event_bus_dual_writes_evidence_stream
    activity = Trace::Log::Event.new(root: @dir, stream: "activity")
    evidence = Trace::Log::Evidence.new(root: @dir)
    bus = Trace::EventBus.new(event_log: activity, evidence_log: evidence)
    bus.publish("ops:commit", head: "abc123")
    bus.publish("scan:complete", count: 1)

    activity_records = activity.recent(5)
    evidence_records = evidence.recent(5)
    assert_equal 2, activity_records.size
    assert_equal 1, evidence_records.size
    assert_equal "ops:commit", evidence_records.first["event"]
  end
end
