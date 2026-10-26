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
      assert_operator File.size("#{path}.1"), :<=, Master::Trace::Log::Event::MAX_BYTES
      assert_operator File.size(path), :<, Master::Trace::Log::Event::MAX_BYTES
    end
  end

  # On a full disk every append failed alike and each printed a line over the
  # prompt, alongside a [SWALLOW-CRITICAL] for every swallowed error.
  def test_a_full_disk_is_reported_once
    Dir.mktmpdir do |dir|
      log = Master::Trace::Log::Event.new(root: dir, stream: "enospc_probe#{Process.pid}")
      File.stub(:open, ->(*) { raise Errno::ENOSPC }) do
        _, err = capture_io { 3.times { assert_nil log.append("some:event") } }

        assert_equal 1, err.lines.size, err
      end
    end
  end

  def test_strict_append_propagates_a_full_disk
    Dir.mktmpdir do |dir|
      log = Master::Trace::Log::Event.new(root: dir, stream: "strict_enospc_probe#{Process.pid}")
      File.stub(:open, ->(*) { raise Errno::ENOSPC }) do
        assert_raises(Errno::ENOSPC) { log.append!("required:event", effect_id: "e-3") }
      end
    end
  end

  def test_enospc_reclaims_a_rotated_generation_and_retries_once
    Dir.mktmpdir do |dir|
      log = Master::Trace::Log::Event.new(root: dir, stream: "activity")
      path = File.join(dir, "runtime", "events", "activity.jsonl")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, %({"event":"old"}\n))
      File.write("#{path}.1", "older events")
      original_open = File.method(:open)
      failed = false
      opener = lambda do |target, *args, **kwargs, &block|
        if target == path && args.first.is_a?(Integer) && args.first.anybits?(File::APPEND) && !failed
          failed = true
          raise Errno::ENOSPC
        end
        original_open.call(target, *args, **kwargs, &block)
      end

      File.stub(:open, opener) do
        record = log.append("recovered:event", value: "kept")
        assert_equal "recovered:event", record.fetch(:event)
      end

      assert failed, "the test did not simulate a full-disk append"
      refute File.exist?("#{path}.1"), "recovery should release the rotated generation"
      assert_equal "recovered:event", log.recent(1).first.fetch("event")
    end
  end

  # The tail cut lands inside the older record; only whole JSONL lines survive.
  def test_compact_rotated_keeps_the_newest_bounded_tail
    Dir.mktmpdir do |dir|
      path = File.join(dir, "oversized.jsonl")
      File.write(path, %({"n":1}\n{"n":2}\n))

      Master::Trace::Log.compact_rotated(path, 10)

      assert_equal %({"n":2}\n), File.read(path)
    end
  end

  def test_scan_hits_rotate_like_the_event_log
    Dir.mktmpdir do |dir|
      path = File.join(dir, "scan_hits.jsonl")
      File.write(path, "x" * 11)

      Master::Trace::Log.rotate(path, 10)

      assert File.exist?("#{path}.1")
      refute File.exist?(path)
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
