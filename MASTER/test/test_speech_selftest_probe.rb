# frozen_string_literal: true

require_relative "test_helper"
require "digest"

# Pins the gap that made `edge_tts_available?` a false positive. It answers with
# two preconditions — the worker file is executable, EventMachine has SSL — and
# bin/tts-worker needs two more before it can speak, rb_edge_tts and
# faye/websocket. On a host missing either, the cheap probe said yes and
# /health reported TTS healthy while synthesis could not start.
#
# The fix is not a longer list in Ruby, which would be the same two-source
# defect one file further on. The worker answers for itself through --selftest,
# and these tests hold that the Ruby side keeps asking it.
class TestSpeechSelftestProbe < Minitest::Test
  Speech = Master::Voice::Speech

  def setup
    reset_memo!
  end

  def teardown
    reset_memo!
  end

  # The worker's own requires are the list. If this fails, the worker cannot
  # speak on this host, and every other assertion here is about the reporting.
  def test_worker_keeps_the_bundle_context_activated_by_entrypoint
    source = File.read(File.join(Master::ROOT, "bin", "tts-worker"))

    refute_match(/BUNDLE_ISOLATION_KEYS\.each\s*\{\s*\|key\|\s*ENV\.delete\(key\)/, source)
    assert_includes source, "Entrypoint.prepare!"
    assert_includes source, 'ENV["BUNDLE_GEMFILE"] = File.join(ROOT, "Gemfile")'
    assert_includes source, "require \"bundler/setup\""
  end

  def test_worker_selftest_exits_zero_and_names_its_versions
    out, err, status = Open3.capture3(RbConfig.ruby, Speech::WORKER, "--selftest", chdir: Master::ROOT)

    assert status.success?, "worker --selftest failed: #{err}"
    assert_match(/\Atts0: selftest ok, /, out)
    assert_match(/rb_edge_tts \d/, out, "the gem the cheap probe cannot see must be named")
    assert_match(/eventmachine \d/, out)
  end

  def test_ready_agrees_with_the_worker_and_reports_no_blocker
    assert Speech.edge_tts_ready?, "expected ready on a host whose worker selftest passes"
    assert_nil Speech.edge_tts_blocker
  end

  # The whole point of memoising: /health calls this per request, and a probe
  # that spawns a subprocess every time is a probe that costs more than the
  # thing it measures.
  def test_the_answer_is_memoised_across_calls
    Speech.edge_tts_ready?
    calls = count_selftest_spawns { 5.times { Speech.edge_tts_ready? } }

    assert_equal 0, calls, "memoised probe re-spawned the worker"
  end

  # Keyed on content, so a lockfile touch without a change (bundler rewrites
  # the file when it re-resolves) cannot invalidate the memo.
  #
  # The mtime is moved with File.utime rather than by running the worker, and
  # that is not laziness. Written the obvious way — run the worker, compare —
  # this test passed against the mtime-keyed version it exists to reject,
  # because File.mtime(...).to_i truncates to whole seconds and the worker
  # returns in 0.3s. A test that only fails when the clock happens to roll over
  # is Scanner Convention 1 in a new costume. Five seconds cannot be truncated
  # away. The lockfile's own mtime is restored either way.
  def test_the_stamp_ignores_a_lockfile_touch
    lock = File.join(Master::ROOT, "Gemfile.lock")
    skip "no Gemfile.lock in this checkout" unless File.file?(lock)

    original = File.mtime(lock)
    before = Speech.send(:selftest_stamp)
    File.utime(original + 5, original + 5, lock)

    assert_equal before, Speech.send(:selftest_stamp),
                 "stamp moved when only the lockfile mtime did, so the memo invalidates itself"
  ensure
    File.utime(original, original, lock) if original
  end

  # The other half, so the key is not merely constant: real content change must
  # invalidate. A stamp that never moves is a memo that never refreshes.
  def test_the_stamp_moves_when_the_lockfile_content_changes
    lock = File.join(Master::ROOT, "Gemfile.lock")
    skip "no Gemfile.lock in this checkout" unless File.file?(lock)

    before = Speech.send(:selftest_stamp)
    Digest::SHA256.stub(:file, ->(_path) { Digest::SHA256.new.update("a different bundle") }) do
      refute_equal before, Speech.send(:selftest_stamp)
    end
  end

  def test_a_missing_worker_is_reported_as_the_blocker_rather_than_a_bare_false
    Speech.stub(:worker_executable?, false) do
      reset_memo!

      refute Speech.edge_tts_ready?
      assert_includes Speech.edge_tts_blocker.to_s, "not executable"
      assert_includes Speech.edge_tts_blocker.to_s, "tts-worker",
                      "the reason must name the path so the reader can check it"
    end
  end

  # A failing worker must surface the worker's own stderr, because that line is
  # what names the missing gem. Losing it leaves the operator with a boolean.
  def test_a_failing_worker_surfaces_its_first_stderr_line
    failed = Struct.new(:success?, :exitstatus).new(false, 70)
    Master::Io::Exec.stub(:capture3, ["", "tts-worker: cannot load such file -- rb_edge_tts\n", failed]) do
      reset_memo!

      refute Speech.edge_tts_ready?
      assert_includes Speech.edge_tts_blocker.to_s, "rb_edge_tts"
      assert_includes Speech.edge_tts_blocker.to_s, "70"
    end
  end

  # The worker narrates before it fails ("deps0: installing bundle"), so the
  # first line named the step and hid the reason. 2026-10-12: /health said only
  # "worker selftest exited : deps0: installing bundle for MASTER".
  def test_a_failing_worker_surfaces_the_reason_at_the_end_of_stderr_not_the_narration
    failed = Struct.new(:success?, :exitstatus).new(false, 78)
    stderr = "deps0: installing bundle for MASTER\nderr: bundle install failed\nderr: Errno::EACCES /root/.master\n"
    Master::Io::Exec.stub(:capture3, ["", stderr, failed]) do
      reset_memo!

      blocker = Speech.edge_tts_blocker.to_s
      assert_includes blocker, "EACCES /root/.master"
      assert_includes blocker, "installing bundle"
    end
  end

  def test_a_killed_probe_says_it_was_killed_rather_than_exited_blank
    killed = Struct.new(:success?, :exitstatus, :termsig).new(false, nil, 9)
    Master::Io::Exec.stub(:capture3, ["", "deps0: installing bundle for MASTER\n", killed]) do
      reset_memo!

      blocker = Speech.edge_tts_blocker.to_s
      assert_includes blocker, "killed"
      assert_includes blocker, "signal 9"
      refute_includes blocker, "exited"
    end
  end

  # A failure that is memoised for good outlives the cause: the deploy's load
  # that made one probe lose is gone in a minute, the 503 would not be.
  def test_a_failed_probe_is_retried_after_the_retry_window
    failed = Struct.new(:success?, :exitstatus).new(false, 1)
    calls = 0
    Master::Io::Exec.stub(:capture3, ->(*_a, **_o) { calls += 1; ["", "boom\n", failed] }) do
      reset_memo!

      Speech.edge_tts_blocker
      Speech.edge_tts_blocker
      assert_equal 1, calls, "a fresh failure must be memoised"

      Speech.instance_variable_set(:@selftest_at, Process.clock_gettime(Process::CLOCK_MONOTONIC) - Speech::SELFTEST_RETRY_S - 1)
      Speech.edge_tts_blocker
      assert_equal 2, calls, "a stale failure must be probed again"
    end
  end

  # The cheap probe keeps its job. It gates the synthesis path, which runs per
  # utterance, and a subprocess there would cost more than the failed attempt
  # it avoids.
  def test_the_cheap_probe_still_spawns_nothing
    calls = count_selftest_spawns { 5.times { Speech.edge_tts_available? } }

    assert_equal 0, calls
  end

  private

  def reset_memo!
    Speech.instance_variable_set(:@selftest_stamp, nil)
    Speech.instance_variable_set(:@selftest_blocker, nil)
    Speech.instance_variable_set(:@selftest_at, nil)
  end

  def count_selftest_spawns
    calls = 0
    original = Master::Io::Exec.method(:capture3)
    Master::Io::Exec.define_singleton_method(:capture3) do |*args, **opts|
      calls += 1 if args.include?("--selftest")
      original.call(*args, **opts)
    end
    yield
    calls
  ensure
    Master::Io::Exec.define_singleton_method(:capture3, original)
  end
end
