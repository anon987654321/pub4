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

  def test_replay_commit_correlates_nearby_events
    repo = File.join(@dir, "repo")
    FileUtils.mkdir_p(repo)
    system("git", "-C", repo, "init", "-q")
    system("git", "-C", repo, "config", "user.email", "test@example.com")
    system("git", "-C", repo, "config", "user.name", "Test")
    File.write(File.join(repo, "README"), "hi\n")
    system("git", "-C", repo, "add", "README")
    system("git", "-C", repo, "commit", "-q", "-m", "seed")
    sha = `git -C #{repo} rev-parse --short HEAD`.strip
    committed_at = `git -C #{repo} show -s --format=%aI HEAD`.strip

    master_root = File.join(repo, "MASTER")
    FileUtils.mkdir_p(File.join(master_root, "runtime", "events"))
    File.write(
      File.join(master_root, "runtime", "events", "activity.jsonl"),
      "{\"timestamp\":\"#{committed_at}\",\"event\":\"ops:commit\",\"payload\":{\"head\":\"#{sha}\"}}\n"
    )

    output = Trace::ReplayReader.new(root: master_root).render(arg: "commit #{sha}")
    assert_includes output, "replay commit"
    assert_includes output, "seed"
    assert_includes output, "ops:commit"
  end

  def test_replay_evidence_reads_operational_stream
    evidence_path = File.join(@events_dir, "evidence.jsonl")
    File.write(evidence_path, "{\"timestamp\":\"2026-06-25T10:00:00Z\",\"event\":\"ops:commit\",\"payload\":{\"head\":\"abc\"}}\n")
    output = Trace::ReplayReader.new(root: @dir).render(arg: "evidence")
    assert_includes output, "replay evidence"
    assert_includes output, "ops:commit"
  end

  def test_replay_failures_filters_error_events
    path = File.join(@events_dir, "activity.jsonl")
    File.write(path, [
      "{\"timestamp\":\"2026-06-25T10:00:00Z\",\"event\":\"scan:complete\",\"payload\":{}}",
      "{\"timestamp\":\"2026-06-25T10:00:01Z\",\"event\":\"scan:error\",\"payload\":{\"error\":\"boom\"}}",
    ].join("\n") + "\n")
    output = Trace::ReplayReader.new(root: @dir).render(arg: "failures")
    assert_includes output, "scan:error"
    refute_includes output, "scan:complete"
  end
end
