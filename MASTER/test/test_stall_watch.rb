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
end
