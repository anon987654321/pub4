# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/trace/recorder"
require "fileutils"
require "json"

class TestTraceRecorderStorage < Minitest::Test
  class EventBus
    def subscribe(_pattern, &_block); end
  end

  def recorder(root)
    Master::Trace::Recorder.new(root:, event_bus: EventBus.new)
  end

  def trace_directory(root)
    File.join(root, ".master", "traces")
  end

  def daily_trace_path(root)
    File.join(trace_directory(root), "#{Time.now.strftime("%Y-%m-%d")}.jsonl")
  end

  def sample_turn
    {
      id: "storage-test", start_ts: Time.now.to_i, channel: "cli",
      message: "private prompt text",
      events: [{ event: "tool:after", query: "https://internal.invalid/?token=trace-secret", ts_ms: 0 }]
    }
  end

  def test_symlinked_trace_directory_is_refused
    Dir.mktmpdir("trace-storage-root") do |root|
      Dir.mktmpdir("trace-storage-outside") do |outside|
        FileUtils.mkdir_p(File.join(root, ".master"), mode: 0o700)
        File.symlink(outside, trace_directory(root))

        assert_raises(IOError) { recorder(root) }
        assert_empty Dir.children(outside)
      end
    end
  end

  def test_symlinked_daily_trace_file_is_not_written_through
    Dir.mktmpdir("trace-storage-file") do |root|
      Dir.mktmpdir("trace-storage-target") do |outside|
        FileUtils.mkdir_p(trace_directory(root), mode: 0o700)
        target = File.join(outside, "target.jsonl")
        File.write(target, "leave this target untouched\n")
        File.chmod(0o600, target)
        path = daily_trace_path(root)
        File.symlink(target, path)

        recorder(root).send(:finalize, sample_turn)

        assert File.symlink?(path)
        assert_equal "leave this target untouched\n", File.read(target)
      end
    end
  end

  def test_existing_trace_mode_is_repaired_before_appending
    Dir.mktmpdir("trace-storage-mode") do |root|
      FileUtils.mkdir_p(trace_directory(root), mode: 0o700)
      path = daily_trace_path(root)
      File.write(path, "{}\n")
      File.chmod(0o644, path)

      recorder(root).send(:finalize, sample_turn)

      assert_equal 0o600, File.stat(path).mode & 0o777
      rows = File.readlines(path)
      assert_equal 2, rows.length
      persisted = JSON.parse(rows.last)
      refute_includes rows.last, "private prompt text"
      refute_includes rows.last, "trace-secret"
      assert_equal 64, persisted.dig("message", "sha256").length
    end
  end

  def test_incomplete_existing_trace_line_is_not_extended
    Dir.mktmpdir("trace-storage-incomplete-tail") do |root|
      FileUtils.mkdir_p(trace_directory(root), mode: 0o700)
      path = daily_trace_path(root)
      original = %({"message":"partial-secret"})
      File.write(path, original)
      File.chmod(0o600, path)

      recorder(root).send(:finalize, sample_turn)

      assert_equal original, File.read(path)
    end
  end

  def test_multiple_processes_keep_complete_trace_lines
    Dir.mktmpdir("trace-storage-parallel-lines") do |root|
      worker_script = <<~'RUBY'
        require "master"
        require "trace/recorder"

        root, worker = ARGV
        bus = Object.new
        bus.define_singleton_method(:subscribe) { |*| }
        recorder = Master::Trace::Recorder.new(root:, event_bus: bus)
        10.times do |index|
          recorder.send(:finalize, {
            id: "#{worker}-#{index}", start_ts: Time.now.to_i,
            channel: "test", message: "private payload", events: []
          })
        end
      RUBY

      workers = 4.times.map do |worker|
        Process.spawn(
          RbConfig.ruby, "-I", File.join(Master::ROOT, "lib"), "-e", worker_script,
          root, worker.to_s, out: File::NULL, err: File::NULL
        )
      end
      statuses = workers.map { |pid| Process.wait2(pid).last }
      assert statuses.all?(&:success?), statuses.map(&:exitstatus).inspect

      path = daily_trace_path(root)
      lines = File.readlines(path)
      assert_equal 40, lines.length
      rows = lines.map { |line| JSON.parse(line) }
      assert_equal 40, rows.map { |row| row.fetch("id") }.uniq.length
      refute_includes lines.join, "private payload"
      assert_equal 0o600, File.stat(path).mode & 0o777
    end
  end

  def test_shared_master_state_directory_keeps_its_canonical_group_access
    Dir.mktmpdir("trace-storage-shared-group") do |root|
      state = File.join(root, ".master")
      Dir.mkdir(state)
      groups = Process.groups - [Process.egid]
      skip "this account belongs to no second group" if groups.empty?

      File.chown(nil, groups.first, state)
      File.chmod(0o770, state)

      recorder(root)

      assert_equal MasterPaths.private_dir_mode(state, 0o700), File.stat(state).mode & 0o7777
      assert_equal 0o700, File.stat(trace_directory(root)).mode & 0o777
    end
  end

  def test_non_private_trace_directory_is_refused
    Dir.mktmpdir("trace-storage-directory-mode") do |root|
      FileUtils.mkdir_p(trace_directory(root), mode: 0o700)
      File.chmod(0o755, trace_directory(root))

      assert_raises(IOError) { recorder(root) }
    end
  end
end
