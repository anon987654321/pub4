# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/cli/activity"

class TestCliActivity < Minitest::Test
  def setup
    @activity = Master::CLI::Activity.new
  end

  def test_fix_progress_becomes_semantic
    @activity.record("fix_loop:pass_start", pass: 2, file_count: 184)
    @activity.record("fix_loop:scan_progress", count: 7)
    @activity.record("rule_loop:fix_applied", rule: "NO_PUTS")

    # The last event was an applied fix, so the loop is repairing.
    assert_equal "fix0: repair pass=2 files=184 violations=7 changes=1",
                 @activity.label
  end

  def test_council_state_is_visible
    @activity.record("fix_loop:pass_start", pass: 1, file_count: 20)
    @activity.record("council:start")
    assert_includes @activity.label(elapsed: 3), "council=reviewing"
  end

  def test_clean_summary_is_compact
    @activity.record("fix_loop:pass_start", pass: 2, file_count: 10)
    @activity.record("fix_loop:scan_progress", count: 0)
    @activity.record("rule_loop:fix_applied", rule: "NO_PUTS")
    @activity.record("fix_loop:clean", pass: 2, consecutive_clean: 2)

    assert_equal "fix0: pass=2 files=10 violations=0 changes=1 state=clean",
                 @activity.fix_summary
  end
end
