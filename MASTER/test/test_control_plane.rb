# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require "tmpdir"
require_relative "../lib/master"

class ControlPlaneSpec < Minitest::Test
  Status = Struct.new(:success?)

  def test_dirty_checkout_waits_before_fetching
    Dir.mktmpdir("master-control") do |root|
      runner = []
      plane = Master::Ops::ControlPlane.new(root:, interval: 5, out: StringIO.new)
      plane.define_singleton_method(:command) do |*argv|
        runner << argv
        { stdout: " M changed\n", stderr: "", status: Status.new(false) }
      end

      plane.cycle

      assert_equal [["git", "-C", File.expand_path("..", root), "status", "--porcelain"]], runner
    end
  end

  def test_main_checkout_pulls_when_origin_is_ahead
    Dir.mktmpdir("master-control") do |root|
      plane = Master::Ops::ControlPlane.new(root:, interval: 5, out: StringIO.new)
      commands = [
        [["git", "-C", File.expand_path("..", root), "branch", "--show-current"], { stdout: "main\n", stderr: "", status: Status.new(true) }],
        [["git", "-C", File.expand_path("..", root), "rev-parse", "HEAD"], { stdout: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", stderr: "", status: Status.new(true) }],
        [["git", "-C", File.expand_path("..", root), "rev-parse", "origin/main"], { stdout: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n", stderr: "", status: Status.new(true) }],
        [["git", "-C", File.expand_path("..", root), "merge-base", "--is-ancestor", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"], { stdout: "", stderr: "", status: Status.new(true) }],
        [["git", "-C", File.expand_path("..", root), "pull", "--ff-only", "origin", "main"], { stdout: "", stderr: "", status: Status.new(true) }],
      ]
      plane.define_singleton_method(:command) { |*argv| commands.shift.fetch(1) }

      plane.send(:synchronize_refs!)

      assert_empty commands
    end
  end

  def test_main_checkout_pushes_when_it_is_ahead
    Dir.mktmpdir("master-control") do |root|
      plane = Master::Ops::ControlPlane.new(root:, interval: 5, out: StringIO.new)
      commands = [
        { stdout: "main\n", stderr: "", status: Status.new(true) },
        { stdout: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n", stderr: "", status: Status.new(true) },
        { stdout: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", stderr: "", status: Status.new(true) },
        { stdout: "", stderr: "", status: Status.new(false) },
        { stdout: "", stderr: "", status: Status.new(true) },
      ]
      seen = []
      plane.define_singleton_method(:command) do |*argv|
        seen << argv
        commands.shift
      end

      plane.send(:synchronize_refs!)

      assert_equal ["git", "-C", File.expand_path("..", root), "push", "origin", "main"], seen.last
    end
  end

  def test_main_checkout_stops_on_divergence
    Dir.mktmpdir("master-control") do |root|
      plane = Master::Ops::ControlPlane.new(root:, interval: 5, out: StringIO.new)
      commands = [
        { stdout: "main\n", stderr: "", status: Status.new(true) },
        { stdout: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", stderr: "", status: Status.new(true) },
        { stdout: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n", stderr: "", status: Status.new(true) },
        { stdout: "", stderr: "", status: Status.new(false) },
        { stdout: "", stderr: "", status: Status.new(false) },
      ]
      plane.define_singleton_method(:command) { |*argv| commands.shift }

      assert_raises(Master::Ops::ControlPlane::CommandError) { plane.send(:synchronize_refs!) }
    end
  end

  def test_cycle_claims_and_releases_the_execution_slot_around_control_work
    Dir.mktmpdir("master-control") do |root|
      plane = Master::Ops::ControlPlane.new(root:, interval: 5, out: StringIO.new)
      observed = []
      plane.define_singleton_method(:clean?) { true }
      plane.define_singleton_method(:fetch!) { observed << Master::Ops::LoopOwner.active.fetch("loop") }
      plane.define_singleton_method(:synchronize_refs!) { observed << Master::Ops::LoopOwner.active.fetch("loop") }
      plane.define_singleton_method(:deploy_if_needed!) { observed << Master::Ops::LoopOwner.active.fetch("loop") }

      plane.cycle

      assert_equal %w[control_plane control_plane control_plane], observed
      assert_nil Master::Ops::LoopOwner.active
    ensure
      Master::Ops::LoopOwner.release
    end
  end

  def test_cycle_rejects_a_non_main_checkout
    Dir.mktmpdir("master-control") do |root|
      plane = Master::Ops::ControlPlane.new(root:, interval: 5, out: StringIO.new)
      calls = 0
      plane.define_singleton_method(:command) do |*argv|
        calls += 1
        if argv[-2, 2] == ["status", "--porcelain"]
          { stdout: "", stderr: "", status: Status.new(true) }
        else
          { stdout: "develop\n", stderr: "", status: Status.new(true) }
        end
      end

      plane.cycle

      assert_equal 2, calls
    end
  end

  def test_process_lock_reclaims_dead_metadata_when_no_process_holds_the_file
    dir = Dir.mktmpdir("master-lock-stale")
    path = File.join(dir, "master.lock")
    File.write(path, JSON.generate(pid: 999_999_999, host: "dead", mode: "cli", at: Time.now.utc.iso8601) + "\n")
    Master::Ops::ProcessLock.stub(:lock_holders, ->(_) { raise "lsof must not be required for stale lock recovery" }) do
      lock = Master::Ops::ProcessLock.acquire!(path:, mode: "test")
      refute_nil lock
      Master::Ops::ProcessLock.release(lock)
    end
  ensure
    FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
  end

  def test_process_lock_does_not_reclaim_a_live_os_lock_with_dead_metadata
    dir = Dir.mktmpdir("master-lock-held")
    path = File.join(dir, "master.lock")
    holder = File.open(path, File::RDWR | File::CREAT, 0o600)
    assert holder.flock(File::LOCK_EX | File::LOCK_NB)
    File.write(path, JSON.generate(pid: 999_999_999, host: "dead", mode: "cli", at: Time.now.utc.iso8601) + "\n")

    lock = Master::Ops::ProcessLock.acquire!(path:, mode: "test")
    assert_nil lock
  ensure
    holder&.flock(File::LOCK_UN) rescue nil
    holder&.close rescue nil
    FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
  end

  def test_process_lock_fd_is_closed_on_exec_unless_explicitly_inherited
    dir = Dir.mktmpdir("master-lock-exec")
    path = File.join(dir, "master.lock")
    lock = Master::Ops::ProcessLock.acquire!(path:, mode: "test")
    refute_nil lock
    assert_equal true, lock.close_on_exec?
    Master::Ops::ProcessLock.release(lock)

    inherited = Master::Ops::ProcessLock.acquire!(path:, mode: "test", inherit_fd: true)
    refute_nil inherited
    assert_equal false, inherited.close_on_exec?
    Master::Ops::ProcessLock.release(inherited)
  ensure
    FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
  end

  def test_process_lock_is_the_single_master_mutex
    dir = Dir.mktmpdir("master-lock")
    path = File.join(dir, "master.lock")
    first = Master::Ops::ProcessLock.acquire!(path:, mode: "test")
    refute_nil first
    begin
      reader, writer = IO.pipe
      child = fork do
        reader.close
        second = Master::Ops::ProcessLock.acquire!(path:, mode: "child")
        writer.write(second ? "locked\n" : "blocked\n")
        writer.close
        Master::Ops::ProcessLock.release(second)
        exit(second ? 1 : 0)
      end
      writer.close
      assert_equal "blocked\n", reader.read
      Process.wait(child)
      assert_equal 0, $?.exitstatus
    ensure
      reader&.close
      writer&.close
      Master::Ops::ProcessLock.release(first)
      FileUtils.remove_entry(dir)
    end
  end

  # The boot e2e tests set MASTER_PROCESS_LOCK_PATH so a live process's
  # inherited lock fd on the checkout's own lock cannot flake a boot that
  # would otherwise succeed; unset, the checkout path stays the default.
  def test_process_lock_env_override_redirects_the_lock_and_defaults_back
    dir = Dir.mktmpdir("master-lock-e2e")
    ENV["MASTER_PROCESS_LOCK_PATH"] = File.join(dir, "boot.lock")
    lock = Master::Ops::ProcessLock.acquire!(mode: "test")
    refute_nil lock
    assert File.file?(File.join(dir, "boot.lock"))

    Master::Ops::ProcessLock.release(lock)

    ENV.delete("MASTER_PROCESS_LOCK_PATH")
    assert_equal File.join(Master::ROOT, ".master", "process.lock"),
                 Master::Ops::ProcessLock.lock_path
  ensure
    ENV.delete("MASTER_PROCESS_LOCK_PATH")
    FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
  end
end
