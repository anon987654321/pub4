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
  def test_worker_selftest_exits_zero_and_names_its_versions
    out, err, status = Open3.capture3(RbConfig.ruby, Speech::WORKER, "--selftest", chdir: Master::ROOT)

    assert status.success?, "worker --selftest failed: #{err}"
    assert_match(/\Atts-worker: ok /, out)
    assert_match(/rb_edge_tts=/, out, "the gem the cheap probe cannot see must be named")
    assert_match(/eventmachine=/, out)
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

  # The trap: bundler/setup inside the worker writes Gemfile.lock, so an
  # mtime-keyed memo is invalidated by the very probe it memoises. Keying on
  # content survives the touch.
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

  # The worker still touches the lockfile, which is the premise of the test
  # above. If this ever fails, that premise is gone and both can be simplified.
  def test_the_worker_still_writes_the_lockfile_it_reads
    lock = File.join(Master::ROOT, "Gemfile.lock")
    skip "no Gemfile.lock in this checkout" unless File.file?(lock)

    original = File.mtime(lock)
    File.utime(original - 30, original - 30, lock)
    system(RbConfig.ruby, Speech::WORKER, "--selftest", out: File::NULL, err: File::NULL, chdir: Master::ROOT)

    refute_equal (original - 30).to_i, File.mtime(lock).to_i,
                 "worker no longer touches the lockfile — the content key is now belt and braces, not load-bearing"
  ensure
    File.utime(original, original, lock) if original
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
