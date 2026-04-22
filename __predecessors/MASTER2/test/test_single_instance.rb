# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/master"

class TestSingleInstance < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @lock_path = File.join(@tmpdir, "master.lock")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def test_acquire_creates_lock_with_pid
    handle = MASTER::SingleInstance.acquire(lock_path: @lock_path)

    assert File.exist?(@lock_path)
    content = File.read(@lock_path)
    assert_includes content, "pid=#{Process.pid}"
  ensure
    handle&.release
  end

  def test_second_acquire_raises
    first = MASTER::SingleInstance.acquire(lock_path: @lock_path)

    err = assert_raises(MASTER::SingleInstance::AlreadyRunningError) do
      MASTER::SingleInstance.acquire(lock_path: @lock_path)
    end

    assert_equal @lock_path, err.lock_path
    assert_equal Process.pid, err.owner_pid
  ensure
    first&.release
  end

  def test_allow_multi_env_bypasses_lock
    ENV["MASTER_ALLOW_MULTI"] = "1"
    handle = MASTER::SingleInstance.acquire(lock_path: @lock_path)
    assert_nil handle
  ensure
    ENV.delete("MASTER_ALLOW_MULTI")
  end
end
