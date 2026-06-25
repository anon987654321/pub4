# frozen_string_literal: true

require_relative "test_helper"

class TestReplayReader < Minitest::Test
  include Master

  def setup
    @dir = Dir.mktmpdir
    @events_dir = File.join(@dir, "runtime", "events")
    FileUtils.mkdir_p(@events_dir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_replay_activity_formats_recent_events
    path = File.join(@events_dir, "activity.jsonl")
    File.write(path, "{\"timestamp\":\"2026-06-25T10:00:00Z\",\"event\":\"scan:complete\",\"payload\":{\"count\":1}}\n")
    output = Trace::ReplayReader.new(root: @dir).render(arg: "5")
    assert_includes output, "replay activity"
    assert_includes output, "scan:complete"
  end

  def test_replay_failures_filters_error_events
    path = File.join(@events_dir, "activity.jsonl")
    File.write(path, [
      "{\"timestamp\":\"2026-06-25T10:00:00Z\",\"event\":\"scan:complete\",\"payload\":{}}",
      "{\"timestamp\":\"2026-06-25T10:00:01Z\",\"event\":\"scan:error\",\"payload\":{\"error\":\"boom\"}}"
    ].join("\n") + "\n")
    output = Trace::ReplayReader.new(root: @dir).render(arg: "failures")
    assert_includes output, "scan:error"
    refute_includes output, "scan:complete"
  end
end