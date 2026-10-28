# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "tmpdir"

class TraceLogAppendJsonlTest < Minitest::Test
  LOG = Master::Trace::Log

  def test_rotation_keeps_active_and_rotated_files_within_the_cap
    Dir.mktmpdir("trace-jsonl-cap-") do |dir|
      path = File.join(dir, "events.ndjson")
      8.times do |index|
        LOG.append_jsonl(
          path,
          { "event" => "metric", "detail" => "x" * 80, "n" => index },
          max_bytes: 400,
          mode: 0o600,
          directory_mode: 0o700,
        )
      end

      assert File.file?("#{path}.1")
      assert_operator File.size(path), :<=, 400
      assert_operator File.size("#{path}.1"), :<=, 400
      File.readlines(path, chomp: true).each { |line| JSON.parse(line) }
      File.readlines("#{path}.1", chomp: true).each { |line| JSON.parse(line) }
      assert_operator File.size("#{path}.1"), :>, 0
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_equal 0o600, File.stat("#{path}.lock").mode & 0o777
      assert_equal 0o700, File.stat(dir).mode & 0o777
    end
  end

  def test_rejects_a_record_larger_than_the_cap
    Dir.mktmpdir("trace-jsonl-oversize-") do |dir|
      path = File.join(dir, "events.ndjson")

      assert_raises(ArgumentError) do
        LOG.append_jsonl(path, { "detail" => "x" * 200 }, max_bytes: 40)
      end
      refute File.exist?(path)
    end
  end

  def test_event_stream_uses_private_serialized_jsonl_appends
    Dir.mktmpdir("trace-event-jsonl-") do |root|
      event_log = Master::Trace::Log::Event.new(root:)
      threads = 8.times.map do |worker|
        Thread.new do
          25.times do |index|
            event_log.append("fixture", worker:, index:)
          end
        end
      end
      threads.each(&:value)

      path = File.join(root, "runtime", "events", "activity.jsonl")
      lines = File.readlines(path, chomp: true)
      assert_equal 200, lines.size
      rows = lines.map { |line| JSON.parse(line) }
      assert_equal 200, rows.size
      assert_equal 200, rows.map { |row| [row.dig("payload", "worker"), row.dig("payload", "index")] }.uniq.size
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_equal 0o700, File.stat(File.dirname(path)).mode & 0o777
    end
  end

  def test_failed_rotation_uses_one_bounded_reclaim_before_append
    Dir.mktmpdir("trace-jsonl-reclaim-") do |dir|
      path = File.join(dir, "events.ndjson")
      File.write(path, "x" * 500)
      reclaim_calls = 0
      reclaim = lambda do |target, mode: 0o600|
        reclaim_calls += 1
        File.chmod(mode, target)
        File.truncate(target, 0)
        true
      end

      LOG.stub(:rotate, nil) do
        LOG.stub(:reclaim, reclaim) do
          LOG.append_jsonl(path, { "event" => "recovered" }, max_bytes: 200)
        end
      end

      assert_equal 1, reclaim_calls
      assert_equal "recovered", JSON.parse(File.readlines(path).last).fetch("event")
      assert_operator File.size(path), :<=, 200
    end
  end

  def test_rotation_makes_an_existing_public_log_private_before_preserving_it
    Dir.mktmpdir("trace-jsonl-rotation-permissions-") do |dir|
      path = File.join(dir, "events.ndjson")
      File.write(path, "x" * 190)
      File.chmod(0o644, path)

      LOG.append_jsonl(path, { "event" => "new" }, max_bytes: 200)

      rotated = "#{path}.1"
      assert File.file?(rotated)
      assert_equal 0o600, File.stat(rotated).mode & 0o777
      assert_equal 0o600, File.stat(path).mode & 0o777
    end
  end

  def test_refuses_a_symlink_lock
    Dir.mktmpdir("trace-jsonl-lock-symlink-") do |dir|
      path = File.join(dir, "events.ndjson")
      lock = "#{path}.lock"
      target = File.join(dir, "external-lock")
      File.write(target, "keep\n")
      File.chmod(0o600, target)
      File.symlink(target, lock)

      assert_raises(ArgumentError) do
        LOG.append_jsonl(path, { "event" => "should-not-write" })
      end
      assert_equal "keep\n", File.read(target)
      assert File.symlink?(lock)
      refute File.exist?(path)
    end
  end

  def test_refuses_a_hard_linked_lock_without_changing_target_permissions
    Dir.mktmpdir("trace-jsonl-lock-hardlink-") do |dir|
      path = File.join(dir, "events.ndjson")
      target = File.join(dir, "lock-target")
      lock = "#{path}.lock"
      File.write(target, "keep\n")
      File.chmod(0o644, target)
      File.link(target, lock)

      assert_raises(ArgumentError) do
        LOG.append_jsonl(path, { "event" => "should-not-write" })
      end
      assert_equal 0o644, File.stat(target).mode & 0o777
      assert_equal "keep\n", File.read(target)
      refute File.exist?(path)
    end
  end

  def test_refuses_a_hard_linked_destination_without_appending
    Dir.mktmpdir("trace-jsonl-destination-hardlink-") do |dir|
      path = File.join(dir, "events.ndjson")
      target = File.join(dir, "external-target")
      File.write(target, "keep\n")
      File.chmod(0o600, target)
      File.link(target, path)

      assert_raises(ArgumentError) do
        LOG.append_jsonl(path, { "event" => "should-not-write" })
      end
      assert_equal "keep\n", File.read(target)
      assert_equal "keep\n", File.read(path)
    end
  end

  def test_rotator_refuses_a_symlinked_active_log
    Dir.mktmpdir("trace-jsonl-rotate-symlink-") do |dir|
      path = File.join(dir, "events.ndjson")
      target = File.join(dir, "external-target")
      File.write(target, "x" * 500)
      File.symlink(target, path)

      assert_raises(ArgumentError) { LOG.rotate(path, 100) }
      assert_equal "x" * 500, File.read(target)
      assert File.symlink?(path)
    end
  end

  def test_rejects_a_log_path_replaced_after_the_file_was_opened
    Dir.mktmpdir("trace-jsonl-path-replaced-") do |dir|
      path = File.join(dir, "events.ndjson")
      replacement = File.join(dir, "replacement.ndjson")
      File.write(path, "original\n")
      File.chmod(0o600, path)

      File.open(path, File::RDWR) do |opened|
        File.rename(path, replacement)
        File.write(path, "different inode\n")
        File.chmod(0o600, path)

        error = assert_raises(ArgumentError) do
          LOG.verify_file_identity!(opened, path, "JSONL destination")
        end
        assert_match(/path changed while opening/, error.message)
        assert_equal "different inode\n", File.read(path)
        assert_equal "original\n", File.read(replacement)
      end
    end
  end

  def test_event_recent_refuses_a_symlinked_log
    Dir.mktmpdir("trace-event-reader-symlink-") do |root|
      Dir.mktmpdir("trace-event-reader-target-") do |outside|
        path = File.join(root, "runtime", "events", "activity.jsonl")
        target = File.join(outside, "private.jsonl")
        FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
        File.write(target, JSON.generate("event" => "private", "payload" => "secret") + "\n")
        File.chmod(0o600, target)
        File.symlink(target, path)

        events = Master::Trace::Log::Event.new(root:)
        assert_empty events.recent(10)
        assert_equal "secret", JSON.parse(File.read(target)).fetch("payload")
      end
    end
  end

  def test_event_recent_refuses_a_hard_linked_log
    Dir.mktmpdir("trace-event-reader-hardlink-") do |root|
      path = File.join(root, "runtime", "events", "activity.jsonl")
      FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
      target = File.join(root, "private.jsonl")
      File.write(target, JSON.generate("event" => "private", "payload" => "secret") + "\n")
      File.chmod(0o600, target)
      File.link(target, path)

      events = Master::Trace::Log::Event.new(root:)
      assert_empty events.recent(10)
      assert_equal "secret", JSON.parse(File.read(target)).fetch("payload")
    end
  end

  def test_refuses_a_symlink_destination
    Dir.mktmpdir("trace-jsonl-symlink-") do |dir|
      path = File.join(dir, "events.ndjson")
      target = File.join(dir, "target.ndjson")
      File.write(target, "keep\n")
      File.symlink(target, path)

      assert_raises(ArgumentError) do
        LOG.append_jsonl(path, { "event" => "should-not-write" })
      end
      assert_equal "keep\n", File.read(target)
    end
  end
end
