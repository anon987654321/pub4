# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require_relative "../lib/operator/lock_sweep"

# The scanner's flock files are never deleted after use, so a day-old, unheld
# file is the only kind the sweep may remove.
class TestLockSweep < Minitest::Test
  def with_locks
    Dir.mktmpdir("lock_sweep") do |dir|
      old = File.join(dir, "old.lock")
      held = File.join(dir, "held.lock")
      fresh = File.join(dir, "fresh.lock")
      [old, held, fresh].each { |path| File.write(path, "") }
      stale_time = Time.now - (Operator::LockSweep::TTL_SECONDS + 60)
      [old, held].each { |path| File.utime(stale_time, stale_time, path) }
      yield dir, old, held, fresh
    end
  end

  def test_dry_run_counts_and_deletes_nothing
    with_locks do |dir, old, held, _fresh|
      assert_equal 2, Operator::LockSweep.sweep(dir, apply: false)
      assert File.exist?(old) && File.exist?(held)
    end
  end

  def test_apply_removes_only_old_unheld_locks
    with_locks do |dir, old, held, fresh|
      File.open(held, File::RDWR) do |file|
        file.flock(File::LOCK_EX)
        assert_equal 1, Operator::LockSweep.sweep(dir, apply: true)
      end
      refute File.exist?(old)
      assert File.exist?(held), "a lock a live scan holds was deleted"
      assert File.exist?(fresh)
    end
  end

  def test_sweep_once_runs_once_per_directory
    with_locks do |dir, old, _held, _fresh|
      assert_operator Operator::LockSweep.sweep_once(dir), :>=, 1
      refute File.exist?(old)
      File.write(old, "")
      File.utime(Time.now - 200_000, Time.now - 200_000, old)
      assert_equal 0, Operator::LockSweep.sweep_once(dir)
      assert File.exist?(old)
    end
  end

  def test_missing_directory_is_nothing_to_sweep
    assert_equal 0, Operator::LockSweep.sweep_once(File.join(Dir.tmpdir, "no-such-lock-dir-#{Process.pid}"))
  end
end
