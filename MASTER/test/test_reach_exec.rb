# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/reach/exec"

class TestReachExec < Minitest::Test
  E = Master::Reach::Exec

  def test_capture2e_merges_streams_and_reports_success
    out, status = E.capture2e("sh", "-c", "echo out; echo err 1>&2")
    assert_includes out, "out"
    assert_includes out, "err"
    assert status.success?
  end

  def test_capture3_splits_streams
    out, err, status = E.capture3("sh", "-c", "printf O; printf E 1>&2")
    assert_equal "O", out
    assert_equal "E", err
    assert status.success?
  end

  def test_capture2_returns_stdout
    out, status = E.capture2("sh", "-c", "printf hi")
    assert_equal "hi", out
    assert status.success?
  end

  def test_non_zero_exit_is_non_success
    _out, status = E.capture2e("sh", "-c", "exit 7")
    refute status.success?
    assert_equal 7, status.exitstatus
  end

  def test_chdir_option_forwards
    out, = E.capture2e("pwd", chdir: "/tmp")
    assert_includes out, "tmp"
  end

  def test_leading_env_hash_forwards
    out, = E.capture2e({ "FOO" => "bar" }, "sh", "-c", "printf %s \"$FOO\"")
    assert_equal "bar", out
  end

  def test_stdin_data_forwards
    out, = E.capture2e("cat", stdin_data: "piped")
    assert_equal "piped", out
  end

  def test_timeout_returns_fast_non_success_and_reaps_tree
    marker = "master_exec_timeout_probe_#{Process.pid}"
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    _out, status = E.capture2e("sh", "-c", "sleep 30 # #{marker}", timeout: 1)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_operator elapsed, :<, 5, "timeout did not fire promptly"
    refute status.success?, "timed-out command should report non-success"

    sleep 0.4
    leftover = `pgrep -f #{marker} 2>/dev/null`.split.size
    assert_equal 0, leftover, "process group not reaped on timeout"
  end
end
