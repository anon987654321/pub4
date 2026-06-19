# frozen_string_literal: true

require_relative "test_helper"

# Eval harness: mean-scores a subject across cases; runner/scorer failures degrade to 0, not crash.
class TestEvalHarness < Minitest::Test
  Case = Master::Judge::EvalHarness::Case

  def harness(cases, runner: nil, scorer: nil)
    runner ||= ->(prompt, input) { "#{prompt}:#{input}" }
    scorer ||= ->(output, expect) { output.to_s.include?(expect.to_s) ? 1.0 : 0.0 }
    Master::Judge::EvalHarness.new(cases: cases, runner: runner, scorer: scorer)
  end

  def test_mean_score_across_cases
    cases = [Case.new(input: "a", expect: "a"), Case.new(input: "b", expect: "ZZZ")]
    assert_in_delta 0.5, harness(cases).score("p"), 0.001
  end

  def test_perfect_and_empty
    assert_equal 1.0, harness([Case.new(input: "x", expect: "x")]).score("p")
    assert_equal 0.0, harness([]).score("p")
  end

  def test_runner_failure_scores_zero_not_crash
    h = harness([Case.new(input: "x", expect: "y")], runner: ->(_p, _i) { raise "boom" }, scorer: ->(_o, _e) { 1.0 })
    assert_equal 0.0, h.score("p")
  end

  def test_clamps_out_of_range_scorer
    h = harness([Case.new(input: "x", expect: "y")], scorer: ->(_o, _e) { 5.0 })
    assert_equal 1.0, h.score("p")
  end

  def test_per_case_report
    report = harness([Case.new(input: "a", expect: "a")]).report("p")
    assert_equal 1, report.size
    assert_equal 1.0, report.first[:score]
  end
end
