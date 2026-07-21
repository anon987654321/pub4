# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../lib/pub4/ci_guard"

class CiGuardTest < Minitest::Test
  def test_enabled_when_env_guard_set
    with_env("PUB4_CI_GUARD" => "1") do
      assert Pub4::CiGuard.enabled?
    end
  end

  def test_disabled_when_env_guard_zero
    with_env("PUB4_CI_GUARD" => "0") do
      refute Pub4::CiGuard.enabled?
    end
  end

  def test_lock_paths_under_var_tmp
    assert_equal "/var/tmp/pub4-ci.lock", Pub4::CiGuard::LOCK_PATH
    assert_equal "/var/tmp/pub4-ci.lock.holder", Pub4::CiGuard::HOLDER_PATH
  end

  # Regression: the requested 0o666 mode on File.open is masked by the
  # creating process's umask (022 strips it to 0644), so a lock file first
  # created by one app's deploy user became unopenable by every other app's
  # deploy user -- Errno::EACCES, defeating the cross-app mutex entirely.
  # This bit amber's deploy in production on 2026-07-20 right after brgen's
  # CI run created the file. chmod isn't subject to umask, so it must be
  # applied explicitly after creation.
  def test_lock_file_is_world_writable_regardless_of_umask
    lock_path = Pub4::CiGuard::LOCK_PATH
    File.delete(lock_path) if File.exist?(lock_path)
    old_umask = File.umask(0o022)
    begin
      Pub4::CiGuard.with_lock { nil }
    ensure
      File.umask(old_umask)
    end
    mode = File.stat(lock_path).mode & 0o777
    assert_equal 0o666, mode, "lock file should be world read/write regardless of umask"
  end

  # Regression: only a file's owner may chmod it, so the very next app to run
  # bin/ci after the fix above hit Errno::EPERM on File.chmod (a different
  # deploy user than whoever created/last-fixed the file) and the whole CI
  # run crashed before ever reaching flock. Bit bsdports's deploy on the same
  # incident (2026-07-20), right after the ownership fix landed for amber.
  # A non-owner's chmod attempt must be tolerated, not fatal -- the mode is
  # already whatever the owner set it to.
  def test_with_lock_tolerates_eperm_on_chmod
    original = File.method(:chmod)
    File.define_singleton_method(:chmod) { |*| raise Errno::EPERM }
    begin
      result = Pub4::CiGuard.with_lock { :yielded }
      assert_equal :yielded, result
    ensure
      File.define_singleton_method(:chmod, original)
    end
  end

  # Regression: chmod-after-open only runs once File.open has already
  # succeeded. A lock file that predates this fix (or was created under a
  # stricter umask) can sit at a stale restrictive mode owned by another
  # user -- opening it for read/write then fails with Errno::EACCES at the
  # OS level, before any chmod call is reached. That must be reported
  # clearly (warn + exit 1), not crash with a raw, uncaught backtrace.
  def test_with_lock_reports_eacces_on_open_instead_of_crashing
    original = File.method(:open)
    File.define_singleton_method(:open) do |*args, &blk|
      raise Errno::EACCES, "Permission denied" if args.first == Pub4::CiGuard::LOCK_PATH

      original.call(*args, &blk)
    end
    begin
      err = assert_raises(SystemExit) { Pub4::CiGuard.with_lock { :yielded } }
      assert_equal 1, err.status
    ensure
      File.define_singleton_method(:open, original)
    end
  end

  # Regression: HOLDER_PATH had the identical umask/ownership bug as
  # LOCK_PATH (plain File.write, no chmod, no rescue) -- writing it as a
  # different user than whoever created it would raise the same
  # Errno::EACCES this whole fix exists to prevent. write_holder! now goes
  # through the same open_shared path as the lock file.
  def test_write_holder_tolerates_eperm_on_chmod
    original = File.method(:chmod)
    File.define_singleton_method(:chmod) { |*| raise Errno::EPERM }
    holder_existed_during_lock = nil
    begin
      result = Pub4::CiGuard.with_lock do
        holder_existed_during_lock = File.exist?(Pub4::CiGuard::HOLDER_PATH)
        :yielded
      end
      assert_equal :yielded, result
      assert holder_existed_during_lock, "holder file should exist while the lock is held"
    ensure
      File.define_singleton_method(:chmod, original)
      File.delete(Pub4::CiGuard::HOLDER_PATH) if File.exist?(Pub4::CiGuard::HOLDER_PATH)
    end
  end

  # Regression: reporting who holds a busy lock read HOLDER_PATH with no
  # rescue -- a holder file written under a stricter umask than this
  # process's, by a different user, would raise Errno::EACCES here instead
  # of falling back to "unknown", crashing the busy-lock path itself.
  def test_safe_read_falls_back_to_unknown_on_eacces
    original = File.method(:read)
    File.define_singleton_method(:read) { |*| raise Errno::EACCES, "Permission denied" }
    begin
      assert_equal "unknown", Pub4::CiGuard.safe_read(__FILE__)
    ensure
      File.define_singleton_method(:read, original)
    end
  end

  private

  def with_env(vars)
    old = vars.keys.to_h { |key| [key, ENV[key]] }
    vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
