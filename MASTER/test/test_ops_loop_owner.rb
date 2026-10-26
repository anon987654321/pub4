# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "json"
require "tmpdir"
require "time"
require_relative "../lib/ops"

class LoopOwnerSpec < Minitest::Test
  def setup
    Master::Ops::LoopOwner.release
  end

  def teardown
    Master::Ops::LoopOwner.release
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
      path = File.join(dir, "owner.json")
      File.write(path, JSON.generate(pid: 123_456, at: Time.now.utc.iso8601))

      Master::Ops::LoopOwner.stub(:dir, dir) do
        Master::Ops::LoopOwner.stub(:info, path) do
          Master::Ops::LoopOwner.stub(:process_alive?, false) do
            Master::Ground::Swallow.stub(:log, nil) do
              Master::Ops::LoopOwner.cleanup_stale!
            end
          end
        end
      end

      refute File.exist?(dir), "a valid dead owner must release the stale loop claim"
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
