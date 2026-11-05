# frozen_string_literal: true

require_relative "test_helper"

# A lane LaneSilence has paused is refused for its cool-off. Those refusals are
# the pause working; counted as failures they dropped the lane for the run, and
# a /fix pinned to one lane failed every file after it.
class TestFixLaneCoolOff < Minitest::Test
  Ledger = Master::Fix::RunLedger
  Silence = Master::Io::LaneSilence

  def setup
    Ledger.reset!
    Master::Io::LaneQuota.clear_run_drops!
  end

  def teardown
    Silence.record(true, Silence.lane_of("hushed:model"))
    Ledger.reset!
    Master::Io::LaneQuota.clear_run_drops!
  end

  def test_refusals_during_a_cool_off_do_not_drop_the_lane
    Silence.silence(Silence.lane_of("hushed:model"), reason: "malformed tool-call response")

    refute Ledger.lane_failed("hushed:model")
    refute Ledger.lane_failed("hushed:model")
    refute Master::Io::LaneQuota.run_drops.key?("hushed")
  end

  def test_failures_outside_a_cool_off_still_drop_the_lane
    refute Ledger.lane_failed("hushed:model")
    assert Ledger.lane_failed("hushed:model")
  end
end
