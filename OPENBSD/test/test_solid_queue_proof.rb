# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "time"
require_relative "../lib/utf8"
require_relative "../solid_queue_proof"

# The gate exists so an app whose jobs never run cannot deploy green. It used to
# assert a registered SolidQueue::Process, which vm23 deliberately does not have
# — rc.d/<app>_jobs is disabled at boot and drain-jobs.sh runs the queue hourly
# instead — so every Rails deploy stamped failed while the app was healthy, and
# `vps-deploy all` could never get past brgen.
#
# Both halves are pinned here. Widening a gate is only safe if the failure it
# was built for is still reachable, so the "nothing is running these jobs" case
# gets as much attention as the passing one.
class SolidQueueProofTest < Minitest::Test
  P = SolidQueueProof

  # The real format, copied from /var/log/drain-jobs.log on vm23.
  LOG = <<~TXT
    2026-08-18T01:08:18Z brgen due 22 -> 2  ahead=54 failed=0 (ran 180s)
    2026-08-18T01:08:19Z amber nothing due (ahead=0 failed=0)
    2026-08-18T01:08:20Z bsdports nothing due (ahead=0 failed=0)
    2026-08-18T02:08:07Z brgen due 11 -> 2  ahead=48 failed=0 (ran 180s)
    2026-08-18T02:08:07Z amber nothing due (ahead=0 failed=0)
  TXT

  def with_log(text = LOG)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "drain-jobs.log")
      File.write(path, text)
      yield path
    end
  end

  def test_it_reads_the_newest_run_for_the_named_app
    with_log do |path|
      assert_equal Time.parse("2026-08-18T02:08:07Z"), P.last_drain_at("brgen", log_path: path)
      assert_equal Time.parse("2026-08-18T02:08:07Z"), P.last_drain_at("amber", log_path: path)
    end
  end

  # "nothing due" is the drain reporting it looked and found no work. That is
  # proof it ran, which is the thing being measured.
  def test_a_nothing_due_line_still_counts_as_a_run
    with_log("2026-08-18T02:08:20Z bsdports nothing due (ahead=0 failed=0)\n") do |path|
      assert P.drain_recent?("bsdports", now: Time.parse("2026-08-18T02:30:00Z"), log_path: path)
    end
  end

  def test_a_recent_drain_passes_and_a_stale_one_does_not
    with_log do |path|
      assert P.drain_recent?("brgen", now: Time.parse("2026-08-18T03:00:00Z"), log_path: path),
             "52 minutes after the last drain is well inside the window"
      refute P.drain_recent?("brgen", now: Time.parse("2026-08-18T09:00:00Z"), log_path: path),
             "seven hours after the last drain the queue is not being worked"
    end
  end

  # The boundary is a decision, not an accident: hourly schedule, two hours so
  # one skipped tick is tolerated and a dead drain is not.
  def test_the_window_is_two_hours
    assert_equal 7200, P::MAX_DRAIN_AGE_S

    with_log do |path|
      base = Time.parse("2026-08-18T02:08:07Z")
      assert P.drain_recent?("brgen", now: base + 7199, log_path: path)
      refute P.drain_recent?("brgen", now: base + 7201, log_path: path)
    end
  end

  # The failure the gate is built for. An app the drain never mentions has
  # nothing running its jobs, and must not pass.
  def test_an_app_the_drain_never_ran_does_not_pass
    with_log do |path|
      refute P.drain_recent?("takeaway", now: Time.parse("2026-08-18T02:30:00Z"), log_path: path)
    end
  end

  def test_a_missing_log_does_not_pass
    refute P.drain_recent?("brgen", now: Time.parse("2026-08-18T02:30:00Z"),
                                    log_path: "/nonexistent/drain-jobs.log")
  end

  # A line whose app column happens to contain the name must not match on a
  # substring — "amber" is not "amberapp".
  def test_the_app_column_matches_exactly
    with_log("2026-08-18T02:08:07Z amberapp nothing due (ahead=0 failed=0)\n") do |path|
      refute P.drain_recent?("amber", now: Time.parse("2026-08-18T02:30:00Z"), log_path: path)
    end
  end

  def test_a_garbled_line_does_not_raise
    with_log("not a log line at all\n\n2026-08-18T02:08:07Z brgen due 1 -> 0\n") do |path|
      assert P.drain_recent?("brgen", now: Time.parse("2026-08-18T02:30:00Z"), log_path: path)
    end
  end

  # The adapter check is the half that must NOT be widened: an app that is not
  # on SolidQueue is misconfigured regardless of who runs the jobs.
  def test_the_runner_still_hard_fails_on_the_wrong_adapter
    src = P.runner_source("amber", 1)

    assert_includes src, "SolidQueueAdapter"
    assert_match(/adapter=.*\n\s*exit 1/m, src, "a non-SolidQueue adapter no longer exits 1")
  end

  # Three, not one, so "no resident worker" is distinguishable from
  # "misconfigured" — the distinction the old script could not make.
  def test_the_runner_reports_no_worker_separately_from_misconfiguration
    src = P.runner_source("amber", 15)

    assert_includes src, "exit 3"
    assert_includes src, "no resident worker registered"
    assert_includes src, "15.times"
  end

  def test_it_looks_once_when_the_drain_already_proves_the_work
    assert_includes P.runner_source("amber", 1), "1.times"
  end
end
