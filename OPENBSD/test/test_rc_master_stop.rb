# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"

# etc/rc.d/master needs OpenBSD's rc.subr, so the stop path cannot run whole here.
# Its helpers sit between two marker lines and are plain ksh; this runs exactly that
# text against stubbed pgrep, pkill, ps, nc and sleep. What it proves: stopping a
# service whose process is already gone exits 0 and says nothing, a daemon that
# survives TERM gets a group KILL, and a port that never frees fails the stop.
class RcMasterStopTest < Minitest::Test
  RC = File.read(File.expand_path("../etc/rc.d/master", __dir__), encoding: "UTF-8")
  HELPERS = RC[/^# --- stop path.*?^# --- end stop path ---$/m]
  # rc_post KILLs the fstat holders too, so their helpers come along.
  HOLDERS = RC[/^# port holders: begin$.*?^# port holders: end$/m]

  def stub(dir, name, body)
    File.write(File.join(dir, name), "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, File.join(dir, name))
  end

  # held: how many nc probes report the port as held before it frees (-1 = forever).
  def run_stop(dir, pids: "", pgid: "", held: 0, call: "rc_stop")
    stub(dir, "pgrep", pids.empty? ? "exit 1" : "echo #{pids}")
    # pgid for the daemon's pid; any other pid (the shell itself) is group 1.
    stub(dir, "ps", pgid.empty? ? "exit 1" : "if echo \"$*\" | grep -q -e '-p #{pids}'; then echo ' #{pgid}'; else echo ' 1'; fi")
    stub(dir, "pkill", %(echo "pkill $*" >> #{dir}/calls))
    stub(dir, "sleep", "exit 0")
    # A test that wants a holder writes fstat.out before calling; none by default.
    stub(dir, "fstat", "cat #{dir}/fstat.out 2>/dev/null")
    File.write(File.join(dir, "held"), held.to_s)
    stub(dir, "nc", <<~SH)
      n=$(cat #{dir}/held)
      [ "$n" = 0 ] && exit 1
      [ "$n" -gt 0 ] && echo $((n - 1)) > #{dir}/held
      exit 0
    SH
    script = <<~SH
      PATH=#{dir}:$PATH; PORT=53187; rc_stop_signal=TERM
      _rc_sendsig() { pkill -${1:-TERM} -xf pexp; }
      #{HELPERS}
      #{HOLDERS}
      #{call}; echo "exit=$?"
    SH
    out = IO.popen(["ksh", "-c", script, { err: %i[child out] }], &:read)
    [out, File.exist?(File.join(dir, "calls")) ? File.read(File.join(dir, "calls")) : ""]
  end

  def test_the_helpers_are_present
    refute_nil HELPERS, "the stop-path markers are gone from etc/rc.d/master"
  end

  def test_stopping_a_service_whose_process_is_gone_exits_zero_quietly
    Dir.mktmpdir do |dir|
      out, calls = run_stop(dir, pids: "87387", pgid: "")
      assert_equal "exit=0\n", out, "a dead pid must produce no noise and no failure"
      refute_match(/-g /, calls, "no group to signal when the process is gone")
    end
  end

  def test_the_kill_wrapper_silences_only_the_timer_signal
    Dir.mktmpdir do |dir|
      out, = run_stop(dir, call: "kill -ALRM 999999; echo alrm=$?; kill -0 999999; echo plain=$?")
      assert_includes out, "alrm=0"
      assert_includes out, "plain=1"
      assert_match(/no such process/i, out, "a real kill failure must still speak")
    end
  end

  def test_a_live_daemon_gets_its_group_signalled_but_never_rcs_own_group
    Dir.mktmpdir do |dir|
      _out, calls = run_stop(dir, pids: "4242", pgid: "4242")
      assert_includes calls, "pkill -TERM -g 4242"
    end
  end

  def test_rcs_own_group_is_never_signalled
    Dir.mktmpdir do |dir|
      _out, calls = run_stop(dir, pids: "4242", pgid: "1")
      refute_match(/-g /, calls)
    end
  end

  def test_a_port_that_frees_in_time_lets_post_succeed
    Dir.mktmpdir do |dir|
      out, calls = run_stop(dir, held: 3, call: "rc_post")
      assert_equal "exit=0\n", out
      refute_includes calls, "KILL"
    end
  end

  def test_a_port_that_never_frees_escalates_to_kill_and_fails_the_stop
    Dir.mktmpdir do |dir|
      out, calls = run_stop(dir, pids: "4242", pgid: "4242", held: -1, call: "rc_post")
      assert_equal "exit=1\n", out
      assert_includes calls, "pkill -KILL -g 4242"
    end
  end

  # 2026-10-28 on vm23: falcon had exited on TERM, so pgrep found no group, and a
  # node child of the worker still held the inherited listener. The fstat holder
  # is KILLed and the stop succeeds once the port frees.
  def test_an_orphaned_port_holder_is_killed_when_falcon_is_gone
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "fstat.out"),
                 "master   node        6067    7* internet stream tcp 0x0 127.0.0.1:53187\n")
      record_kill = %(kill() { echo "kill $*" >> #{dir}/calls; })

      out, calls = run_stop(dir, held: 12, call: "#{record_kill}; rc_post")
      assert_equal "exit=0\n", out
      assert_includes calls, "kill -KILL 6067"
    end
  end

  def test_start_refuses_while_the_port_is_held
    pre = RC[/^rc_pre\(\) \{.*?^\}$/m]
    assert_match(/master_wait_port_free 20/, pre)
    assert_match(/still held after TERM and KILL, refusing to start/, pre)
  end
end
