# frozen_string_literal: true

require_relative "test_helper"

class TestEventLogRotation < Minitest::Test
  # activity.jsonl was append-only with no cap and grew to 1.2GB, filling
  # the disk and crashing an in-progress /fix round (every event append
  # after that point silently failed with ENOSPC). Rotation must kick in
  # before appending, not after, so a single oversized file never blocks
  # forever waiting for someone to notice.
  def test_appends_past_the_size_cap_rotate_instead_of_growing_forever
    Dir.mktmpdir do |dir|
      log = Master::Trace::Log::Event.new(root: dir, stream: "activity")
      path = File.join(dir, "runtime", "events", "activity.jsonl")

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "x" * (Master::Trace::Log::Event::MAX_BYTES + 1))

      log.append("some:event", key: "value")

      assert File.exist?("#{path}.1"), "oversized log should be rotated aside, not appended to"
      assert File.exist?(path), "a fresh log file should exist after rotation"
      assert_operator File.size(path), :<, Master::Trace::Log::Event::MAX_BYTES
    end
  end

  def test_appends_under_the_size_cap_do_not_rotate
    Dir.mktmpdir do |dir|
      log = Master::Trace::Log::Event.new(root: dir, stream: "activity")
      path = File.join(dir, "runtime", "events", "activity.jsonl")

      log.append("first:event")
      log.append("second:event")

      refute File.exist?("#{path}.1"), "a small log should never rotate"
      assert_equal 2, log.recent(10).size
    end
  end
end
