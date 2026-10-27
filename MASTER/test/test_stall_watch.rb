# frozen_string_literal: true

require_relative "test_helper"
require "operator/stall_watch"
require "tmpdir"

class TestStallWatch < Minitest::Test
  STALLED = "fix0: STALLED pass 1 phase scan + stream fixes for %dm, 0 files attempted\n"

  def test_the_longest_reported_stall_counts
    log = (STALLED % 3) + (STALLED % 12) + (STALLED % 11)
    assert_equal 720, Operator::StallWatch.stalled_seconds(log)
  end

  def test_a_healthy_log_never_aborts
    refute Operator::StallWatch.abort?("fix0: pass 1/8 files 40/1651 fixes 3 ok\n")
  end

  def test_abort_waits_for_the_limit
    refute Operator::StallWatch.abort?(STALLED % 9, env: {})
    assert Operator::StallWatch.abort?(STALLED % 10, env: {})
  end

  def test_the_limit_is_configurable_and_a_bad_value_falls_back
    assert Operator::StallWatch.abort?(STALLED % 2, env: { "MASTER_FIX_ABORT_S" => "60" })
    assert_equal 600, Operator::StallWatch.limit({ "MASTER_FIX_ABORT_S" => "soon" })
  end

  def test_tail_reads_only_the_end_of_a_long_log
    Dir.mktmpdir do |dir|
      path = File.join(dir, "fix.log")
      File.write(path, ("old line\n" * 5000) + (STALLED % 14))
      text = Operator::StallWatch.tail(path, bytes: 200)
      assert_operator text.bytesize, :<=, 200
      assert Operator::StallWatch.abort?(text, env: {})
    end
    assert_equal "", Operator::StallWatch.tail("/nonexistent/fix.log")
  end

  # A RAILS run spent fifty-six minutes before its first repair and said nothing about it; the
  # next run opens with how long the last one took to get there.
  LOG = <<~LOG
    fix0: pass 0/60 source0 files 0/10 (0%) fixes 0 ok 0 failed elapsed = 240s (4m00s) eta unknown
    fix0: pass 0/60 source0 files 0/10 (0%) fixes 0 ok 0 failed elapsed = 600s (10m00s) eta unknown
    fix0: pass 0/60 reach0 files 0/10 (0%) fixes 0 ok 0 failed elapsed = 2000s (33m20s) eta unknown
    fix0: pass 1/60 fix0 phase fast fixes files 0/10 (0%) fixes 0 ok 0 failed elapsed = 3390s (56m30s) eta unknown
  LOG

  def test_the_plan_names_each_stage_once_and_when_repairs_began
    Dir.mktmpdir do |dir|
      log = File.join(dir, "fix-RAILS.log")
      File.write(log, LOG)

      line = Operator::RunPlan.line("RAILS", log)

      assert_includes line, "last RAILS run: source 4m, reach 33m; repairs began at 56m"
    end
  end

  def test_without_an_earlier_run_the_plan_says_so
    assert_match(/no earlier STUDIO run/, Operator::RunPlan.line("STUDIO", "/nonexistent/fix-STUDIO.log"))
  end
end
