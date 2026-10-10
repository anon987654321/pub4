# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/operator/gate_regression"

class TestGateRegression < Minitest::Test
  Result = Struct.new(:stage, :state, :body, keyword_init: true)

  def failed(stage, *lines) = Result.new(stage:, state: "failed", body: lines)
  def green(stage) = Result.new(stage:, state: "ok", body: [])

  def baseline(*results) = Operator::GateRegression.snapshot(results)
  def regressions(base, *now) = Operator::GateRegression.new(base).regressions(now)

  def test_a_standing_failure_that_is_unchanged_is_not_a_regression
    line = "measure0: spine.core_files 9 / 7 OVER +2 (MASTER/data/spine.yml)"
    base = baseline(failed("ratchets", line))

    assert_empty regressions(base, failed("ratchets", line))
  end

  def test_a_standing_failure_that_shrinks_is_not_a_regression
    base = baseline(failed("ratchets", "measure0: spine.core_files 9 / 7 OVER +2"))

    assert_empty regressions(base, failed("ratchets", "measure0: spine.core_files 8 / 7 OVER +1"))
  end

  def test_a_standing_over_count_that_grows_is_a_regression
    base = baseline(failed("ratchets", "measure0: spine.core_files 9 / 7 OVER +2"))
    found = regressions(base, failed("ratchets", "measure0: spine.core_files 10 / 7 OVER +3"))

    assert_equal 1, found.size
    assert_match(/grew/, found.first)
  end

  def test_a_new_failing_line_is_a_regression
    base = baseline(failed("ratchets", "measure0: spine.core_files 9 / 7 OVER +2"))
    found = regressions(base, failed("ratchets", "measure0: spine.core_files 9 / 7 OVER +2", "measure0: namespace 3 / 2 OVER +1"))

    assert_equal 1, found.size
    assert_match(/new/, found.first)
  end

  def test_a_stage_that_was_green_and_now_fails_is_a_regression
    base = baseline(green("lexical"), failed("ratchets", "x OVER +1"))
    found = regressions(base, failed("lexical", "law0: violation in a.rb"), failed("ratchets", "x OVER +1"))

    assert_equal ["lexical was green and now fails"], found
  end

  def test_ansi_colour_does_not_make_a_line_look_new
    base = baseline(failed("ratchets", "measure0: a 9 / 7 OVER +2"))

    assert_empty regressions(base, failed("ratchets", "\e[31mmeasure0: a 9 / 7 OVER +2\e[0m"))
  end
end
