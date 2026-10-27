# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "json"
require "tmpdir"
require "time"
require "socket"
require "rbconfig"
require_relative "../lib/ops"

class LoopOwnerSpec < Minitest::Test
  # A tmp slot keeps these tests off the checkout's real claim, which a live
  # /fix on this machine may hold.
  def setup
    @slot_root = Dir.mktmpdir("loop-owner-slot-")
    @previous_dir = ENV["MASTER_ACTIVE_LOOP_DIR"]
    ENV["MASTER_ACTIVE_LOOP_DIR"] = File.join(@slot_root, "active_loop")
  end

  def teardown
    Master::Ops::LoopOwner.release
    ENV["MASTER_ACTIVE_LOOP_DIR"] = @previous_dir
    FileUtils.rm_rf(@slot_root)
  end

  def write_claim(**fields)
    dir = Master::Ops::LoopOwner.dir
    FileUtils.mkdir_p(dir)
    File.write(Master::Ops::LoopOwner.info, JSON.generate(fields))
    dir
  end

  def test_live_owner_older_than_the_stale_window_keeps_its_claim
    dir = write_claim(loop: "fix", pid: Process.pid, host: Socket.gethostname,
                      at: (Time.now.utc - (Master::Ops::LoopOwner::STALE_SECONDS * 5)).iso8601)

    Master::Ops::LoopOwner.cleanup_stale!

    assert File.directory?(dir), "a live owner's claim must survive however long its run takes"
    assert_equal "fix", Master::Ops::LoopOwner.active.fetch("loop")
  end

  def test_dead_local_owner_is_released_without_a_swallow_row
    dead = Process.spawn(RbConfig.ruby, "-e", "exit 0")
    Process.wait(dead)
    dir = write_claim(loop: "fix", pid: dead, host: Socket.gethostname, at: Time.now.utc.iso8601)
    errors = []

    Master::Ground::Swallow.stub(:log, ->(*args, **kwargs) { errors << [args, kwargs] }) do
      Master::Ops::LoopOwner.cleanup_stale!
    end

    refute File.exist?(dir), "a dead owner's claim must be released"
    assert_empty errors, "ESRCH means the owner is gone, not a swallowed failure"
  end

  def test_foreign_host_claim_ages_out
    dir = write_claim(loop: "fix", pid: Process.pid, host: "elsewhere.invalid",
                      at: (Time.now.utc - (Master::Ops::LoopOwner::STALE_SECONDS + 60)).iso8601)

    Master::Ops::LoopOwner.cleanup_stale!

    refute File.exist?(dir), "a claim from another host can only age out"
  end

  def test_release_leaves_another_owners_claim_alone
    dir = write_claim(loop: "control_plane", pid: Process.ppid, host: Socket.gethostname,
                      at: Time.now.utc.iso8601)

    Master::Ops::LoopOwner.release

    assert File.directory?(dir), "release must remove only this process's claim"
    assert_equal "control_plane", Master::Ops::LoopOwner.active.fetch("loop")
  end

  def test_claim_records_active_loop
    assert Master::Ops::LoopOwner.claim("watcher")
    active = Master::Ops::LoopOwner.active
    assert_equal "watcher", active["loop"]
    assert active["pid"]
  end

  def test_second_claim_fails_until_release
    assert Master::Ops::LoopOwner.claim("watcher")
    refute Master::Ops::LoopOwner.claim("autofix")
    Master::Ops::LoopOwner.release
    assert Master::Ops::LoopOwner.claim("autofix")
  end

  def test_with_claim_releases_after_block
    result = Master::Ops::LoopOwner.with_claim("watcher") { :ok }
    assert_equal :ok, result
    assert_nil Master::Ops::LoopOwner.active
  end

  def test_valid_pid_and_timestamp_are_accepted_without_logging
    Dir.mktmpdir("loop-owner-valid-") do |dir|
      path = File.join(dir, "owner.json")
      File.write(path, JSON.generate(pid: Process.pid, at: Time.now.utc.iso8601))
      errors = []

      Master::Ops::LoopOwner.stub(:dir, dir) do
        Master::Ops::LoopOwner.stub(:info, path) do
          Master::Ground::Swallow.stub(:log, ->(*args, **kwargs) { errors << [args, kwargs] }) do
            Master::Ops::LoopOwner.cleanup_stale!
          end
        end
      end

      assert File.file?(path), "a live owner with valid metadata must retain its claim"
      assert_empty errors, "a valid numeric PID must not be classified as malformed"
    end
  end

  def test_dead_owner_with_valid_numeric_pid_is_released
    Dir.mktmpdir("loop-owner-dead-") do |dir|
      claim_dir = File.join(dir, "active_loop")
      FileUtils.mkdir_p(claim_dir)
      path = File.join(claim_dir, "owner.json")
      File.write(path, JSON.generate(pid: 123_456, at: Time.now.utc.iso8601))

      Master::Ops::LoopOwner.stub(:dir, claim_dir) do
        Master::Ops::LoopOwner.stub(:info, path) do
          Master::Ops::LoopOwner.stub(:process_alive?, false) do
            Master::Ground::Swallow.stub(:log, nil) do
              Master::Ops::LoopOwner.cleanup_stale!
            end
          end
        end
      end

      refute File.exist?(claim_dir), "a valid dead owner must release the stale loop claim"
    end
  end

  def test_corrupt_timestamp_does_not_release_a_live_owner
    Dir.mktmpdir("loop-owner-corrupt-") do |dir|
      path = File.join(dir, "owner.json")
      File.write(path, JSON.generate(pid: Process.pid, at: "not-an-iso-timestamp"))

      Master::Ops::LoopOwner.stub(:dir, dir) do
        Master::Ops::LoopOwner.stub(:info, path) do
          Master::Ground::Swallow.stub(:log, nil) do
            Master::Ops::LoopOwner.cleanup_stale!
          end
          assert File.file?(path), "corrupt timestamp must not delete a live process claim"
        end
      end
    end
  end

  def test_malformed_pid_does_not_release_a_claim
    Dir.mktmpdir("loop-owner-pid-") do |dir|
      path = File.join(dir, "owner.json")
      File.write(path, JSON.generate(pid: "not-a-pid", at: Time.now.utc.iso8601))

      Master::Ops::LoopOwner.stub(:dir, dir) do
        Master::Ops::LoopOwner.stub(:info, path) do
          Master::Ground::Swallow.stub(:log, nil) do
            Master::Ops::LoopOwner.cleanup_stale!
          end
          assert File.file?(path), "malformed PID must not cause stale-claim deletion"
        end
      end
    end
  end
end
