# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/guard_state"

# amber and bsdports get shed and stay down, and nothing says so.
#
# relayd answers TLS on their behalf while they are down, so the outage reads as
# a hang rather than a 5xx and every other check on the box passes.
# TODO.md has carried "amber_bsdports_stop_and_stay_down" for
# exactly this, and each occurrence was found by a person noticing amber was off
# — including 2026-08-14, when two concurrent deploys shed both and the guard
# did not bring either back.
#
# An earlier version of this rule asked whether resource_guard.sh's restore
# thresholds were still reachable, computed from its history log. Measured
# against the real 1550-tick log it stayed silent through the incident it was
# written for, so it was replaced rather than shipped: the gate does open, just
# rarely, and the log never records whether anything was shed at the time. The
# rule below observes the outage instead of modelling the mechanism.
class TestGuardState < Minitest::Test
  ALL_UP = ->(_svc) { true }
  ALL_DOWN = ->(_svc) { false }

  def test_reports_a_shed_service_that_is_still_down
    message = Deploy::GuardState.shed_and_down(shed: "amber\nbsdports\n", running: ALL_DOWN)

    refute_nil message
    assert_match(/amber, bsdports shed and still down/, message)
    assert_match(/relayd answers TLS/, message, "the message should say why nothing else reports it")
    assert_match(/rcctl restart amber/, message, "name the command that fixes it")
  end

  def test_reports_only_the_ones_actually_down
    up_only_amber = ->(svc) { svc == "amber" }
    message = Deploy::GuardState.shed_and_down(shed: "amber\nbsdports\n", running: up_only_amber)

    assert_match(/bsdports shed and still down/, message)
    refute_match(/amber,/, message)
  end

  def test_silent_when_everything_shed_is_back_up
    assert_nil Deploy::GuardState.shed_and_down(shed: "amber\nbsdports\n", running: ALL_UP)
  end

  def test_silent_when_nothing_is_shed
    assert_nil Deploy::GuardState.shed_and_down(shed: "", running: ALL_DOWN)
    assert_nil Deploy::GuardState.shed_and_down(shed: "\n \n", running: ALL_DOWN)
  end

  # The guard removes an entry only when its own restore path runs. A service
  # that is listed and running therefore proves restore did not bring it back —
  # something else did, and the list is now lying about the state of the box.
  # This is the state vm23 was left in on 2026-08-14: both apps up, both still
  # listed, unchanged across three further guard ticks.
  def test_names_entries_left_behind_by_a_restore_that_never_ran
    assert_equal %w[amber bsdports],
                 Deploy::GuardState.stale_entries(shed: "amber\nbsdports\n", running: ALL_UP)
    assert_empty Deploy::GuardState.stale_entries(shed: "amber\n", running: ALL_DOWN)
  end

  # The thresholds are not asserted as numbers — they are recalibrated as the box
  # changes, and have been twice. What must hold across recalibrations is that
  # restore sits above warn, or shed and restore chase each other.
  def test_the_guard_keeps_hysteresis_between_shed_and_restore
    # encoding: named, not inherited. Under a C locale — which is how the
    # integrity chain invokes everything on vm23 — Ruby reads files as US-ASCII,
    # and resource_guard.sh's comments are full of em-dashes. A bare File.read
    # passed on a Mac and raised "invalid byte sequence in US-ASCII" on the box.
    guard = File.read(File.expand_path("../resource_guard.sh", __dir__), encoding: "UTF-8")
    warn_at = guard[/^MEM_WARN=(\d+)/, 1].to_i
    restore_at = guard[/^MEM_RESTORE=(\d+)/, 1].to_i

    assert_operator warn_at, :>, 0, "MEM_WARN is no longer parseable — this test is asserting nothing"
    assert_operator restore_at, :>, warn_at,
                    "no hysteresis: the guard would shed and restore around one threshold"
  end
end
