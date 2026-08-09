# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "socket"
require "tmpdir"

# Pins the two halves of the 2026-08-01 worker leak: a replacement must retire
# its predecessor, and a merely-busy worker must not be mistaken for a dead one.
#
# What the leak looked like in production: tts-worker is single-threaded, so one
# mid-synthesis cannot answer socket_alive?'s 1s health ping. The supervisor read
# that as death, unlinked the socket and spawned a replacement without stopping
# the original, which then lived forever on an unreachable path. 21 workers were
# holding 309 MB of a 1007 MB box, growing by one a minute — which both starved
# the box into shedding amber/bsdports and forced a cold Ruby+Bundler+EventMachine
# start on nearly every request, so speech took ~20s instead of ~2s.
class TestTtsSupervisor < Minitest::Test
  Sup = Master::Voice::TtsSupervisor

  def setup
    @pids = Sup.instance_variable_get(:@daemon_pids)
    @strikes = Sup.instance_variable_get(:@busy_strikes)
    @saved = [@pids.dup, @strikes.dup]
    @spawned = []
  end

  def teardown
    @spawned.each do |pid|
      Process.kill("KILL", pid)
    rescue Errno::ESRCH
      nil
    end
    @pids.replace(@saved[0])
    @strikes.replace(@saved[1])
  end

  def stub_daemon
    pid = Process.spawn("sleep", "60", out: File::NULL, err: File::NULL)
    Process.detach(pid)
    @spawned << pid
    pid
  end

  def test_retire_daemon_stops_the_predecessor
    slot = 99
    pid = stub_daemon
    @pids[slot] = pid
    assert Sup.process_alive?(pid), "stub daemon should be running before retire"

    Sup.retire_daemon(slot)

    refute Sup.process_alive?(pid), "retire_daemon left the old worker running — this is the leak"
    assert_nil @pids[slot], "retired slot must not keep pointing at a dead pid"
  end

  def test_retire_daemon_is_safe_when_nothing_was_spawned
    @pids.delete(98)
    assert_nil Sup.retire_daemon(98)
  end

  def test_busy_worker_is_not_replaced_until_it_stops_answering_repeatedly
    Dir.mktmpdir("master_tts_busy") do |dir|
      path = File.join(dir, "tts-0.sock")
      server = UNIXServer.new(path)   # a socket nobody answers on: "busy"
      slot = 97
      @pids[slot] = stub_daemon
      @strikes.delete(slot)

      # The first probes must read as busy, so the caller queues on the socket
      # instead of throwing away an in-flight synthesis.
      assert Sup.busy_not_dead?(path, slot), "first silent probe must read as busy"
      assert Sup.busy_not_dead?(path, slot), "second silent probe must read as busy"
      # ...but a worker that never answers is genuinely wedged and gets replaced.
      refute Sup.busy_not_dead?(path, slot), "a worker silent #{Sup::BUSY_STRIKES}x must be replaced"
    ensure
      server&.close
    end
  end

  # The 2026-08-09 wedge: .master/tts-worker-0.starting stood for a day after a
  # spawn died between mkdir and rmdir, so slot 0 of the pool answered false after
  # burning START_TIMEOUT_S, on every call, forever.
  def test_with_daemon_lock_breaks_an_abandoned_lock_instead_of_waiting_it_out
    Dir.mktmpdir("master_tts_lock") do |dir|
      lock = Sup.lock_path(dir, index: 0)
      FileUtils.mkdir_p(File.dirname(lock))
      Dir.mkdir(lock, 0o700)
      abandoned = Time.now - (Sup::STALE_LOCK_S + 1)
      File.utime(abandoned, abandoned, lock)

      ran = false
      started = Time.now
      Sup.with_daemon_lock(dir, index: 0) { ran = true }

      assert ran, "an abandoned lock must be broken, not waited out"
      assert_operator Time.now - started, :<, Sup::START_TIMEOUT_S,
                      "breaking an abandoned lock must not cost the full start timeout"
      refute Dir.exist?(lock), "the lock must be released once the block returns"
    end
  end

  def test_a_lock_a_live_holder_just_took_is_left_alone
    Dir.mktmpdir("master_tts_fresh_lock") do |dir|
      lock = Sup.lock_path(dir, index: 0)
      FileUtils.mkdir_p(File.dirname(lock))
      Dir.mkdir(lock, 0o700)

      refute Sup.break_stale_lock(lock), "a lock younger than STALE_LOCK_S belongs to somebody"
      assert Dir.exist?(lock), "a live holder's lock must survive the probe"
    end
  end

  def test_dead_pid_is_never_treated_as_busy
    Dir.mktmpdir("master_tts_dead") do |dir|
      path = File.join(dir, "tts-0.sock")
      server = UNIXServer.new(path)
      slot = 96
      pid = stub_daemon
      Process.kill("KILL", pid)
      # stub_daemon detaches, so a reaper thread collects it — waitpid here would
      # raise ECHILD. Poll for the pid to actually disappear instead.
      50.times { break unless Sup.process_alive?(pid); sleep 0.02 }
      @pids[slot] = pid
      @strikes.delete(slot)

      refute Sup.busy_not_dead?(path, slot), "a dead worker must be replaced immediately"
    ensure
      server&.close
    end
  end
end
