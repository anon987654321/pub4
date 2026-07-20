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

  private

  def with_env(vars)
    old = vars.keys.to_h { |key| [key, ENV[key]] }
    vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
