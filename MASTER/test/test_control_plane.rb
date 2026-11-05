# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

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

  def test_main_checkout_refuses_to_push_when_it_is_ahead
    Dir.mktmpdir("master-control") do |root|
      out = StringIO.new
      seen = []
      plane = ahead_plane(root:, out:, seen:)

      plane.cycle

      assert_match(/local main is ahead of origin\/main/, out.string)
      refute(seen.any? { |argv| argv.include?("push") })
    end
  end

  def ahead_plane(root:, out:, seen:)
    plane = Master::Ops::ControlPlane.new(root:, interval: 5, out:)

    commands = [
      { stdout: "main\n", stderr: "", status: Status.new(true) },
      { stdout: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n", stderr: "", status: Status.new(true) },
      { stdout: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", stderr: "", status: Status.new(true) },
      { stdout: "", stderr: "", status: Status.new(false) },
      { stdout: "", stderr: "", status: Status.new(true) },
    ]

    plane.define_singleton_method(:clean?) { true }
    plane.define_singleton_method(:fetch!) { nil }
    plane.define_singleton_method(:command) do |*argv|
      seen << argv
      commands.shift
    end

    plane
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

  # cycle claims the slot before it deploys, so its own claim must not read as a busy slot.
  def test_cycle_deploys_under_its_own_claim
    Dir.mktmpdir("master-control") do |root|
      plane = Master::Ops::ControlPlane.new(root:, interval: 5, out: StringIO.new)
      deployed = []
      plane.define_singleton_method(:clean?) { true }
      plane.define_singleton_method(:fetch!) { nil }
      plane.define_singleton_method(:synchronize_refs!) { nil }
      plane.define_singleton_method(:text_command) { |*_argv| "c" * 40 }
      plane.define_singleton_method(:save_state) { |_sha, _status| nil }
      plane.define_singleton_method(:run_deploy) do |*argv|
        deployed << argv
        ["", "", Status.new(true)]
      end

      plane.cycle

      assert_equal 1, deployed.size, "the control plane never deployed under its own slot claim"
    ensure
      Master::Ops::LoopOwner.release
    end
  end

  def test_cycle_rejects_a_non_main_checkout
    Dir.mktmpdir("master-control") do |root|
      out = StringIO.new
      plane = Master::Ops::ControlPlane.new(root:, interval: 5, out:)
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

      # status, fetch, then the branch check that stops the cycle.
      assert_equal 3, calls
      assert_match(/requires the main branch/, out.string)
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

  def test_a_waiting_acquire_queues_until_the_holder_lets_go
    dir = Dir.mktmpdir("master-lock-wait")
    path = File.join(dir, "master.lock")
    holder = Master::Ops::ProcessLock.acquire!(path:, mode: "interactive")
    waited_on = []
    sleeper = lambda do |_seconds|
      Master::Ops::ProcessLock.release(holder) if waited_on.size == 2
    end

    lock = Master::Ops::ProcessLock.acquire_waiting!(path:, mode: "headless", wait: 60, sleeper:) do |owner|
      waited_on << owner["mode"]
    end

    refute_nil lock, "the queued run never got the lock after the holder released it"
    assert_equal %w[interactive interactive], waited_on.first(2)
    Master::Ops::ProcessLock.release(lock)
  ensure
    FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
  end

  def test_a_waiting_acquire_gives_up_at_its_deadline
    dir = Dir.mktmpdir("master-lock-deadline")
    path = File.join(dir, "master.lock")
    holder = Master::Ops::ProcessLock.acquire!(path:, mode: "interactive")
    now = 0
    clock = -> { now }
    sleeper = ->(seconds) { now += seconds }

    lock = Master::Ops::ProcessLock.acquire_waiting!(path:, mode: "headless", wait: 12, poll: 5, sleeper:, clock:)

    assert_nil lock
    assert_equal 15, now, "it should poll until the deadline, then stop"
  ensure
    Master::Ops::ProcessLock.release(holder) if holder
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

  # `bin/master --status` reads the frame an operator needs before waiting on
  # a held lock: holder, mode, held-for and last session activity. Read-only —
  # the report must answer while the lock is held, so it never takes the lock.
  def test_status_report_names_the_holder_mode_and_held_for
    Dir.mktmpdir("master-lock-status") do |root|
      lock_dir = File.join(root, ".master")
      FileUtils.mkdir_p(lock_dir)
      lock = Master::Ops::ProcessLock.acquire!(path: File.join(lock_dir, "process.lock"), mode: "interactive")

      lines = Master::Ops::ProcessLock.status_report(root:)

      assert lines.grep(/lock held by pid=#{Process.pid}/).any?, lines.join("\n")
      assert lines.grep(/mode=interactive/).any?, lines.join("\n")
      assert lines.grep(/held for/).any?, lines.join("\n")

      Master::Ops::ProcessLock.release(lock)

      free = Master::Ops::ProcessLock.status_report(root:)

      assert free.grep(/control plane idle/).any?, free.join("\n")
    end
  end

  def test_status_report_reads_last_session_activity_from_the_transcript
    Dir.mktmpdir("master-lock-status") do |root|
      lock_dir = File.join(root, ".master")
      FileUtils.mkdir_p(lock_dir)
      transcript = File.join(lock_dir, "session.json")
      File.write(transcript, '{"messages":[]}')
      past = Time.now - (2 * 3600)
      File.utime(past, past, transcript)

      lines = Master::Ops::ProcessLock.status_report(root:)

      assert lines.grep(/last session activity 2h/).any?, lines.join("\n")
    end
  end

  def test_status_report_says_so_when_nothing_holds_anything
    Dir.mktmpdir("master-lock-status") do |root|
      lines = Master::Ops::ProcessLock.status_report(root:)

      assert lines.grep(/control plane idle/).any?, lines.join("\n")
    end
  end

  def test_held_for_durations_read_like_an_operator_reads_them
    now = Time.utc(2026, 11, 5, 12, 0, 0)

    assert_equal "45s", Master::Ops::ProcessLock.duration_since("2026-11-05T11:59:15Z", now:)
    assert_equal "12m 0s", Master::Ops::ProcessLock.duration_since("2026-11-05T11:48:00Z", now:)
    assert_equal "13h 0m", Master::Ops::ProcessLock.duration_since("2026-11-04T23:00:00Z", now:)
    assert_nil Master::Ops::ProcessLock.duration_since("not-a-timestamp", now:)
    assert_nil Master::Ops::ProcessLock.duration_since(nil, now:)
  end
end
