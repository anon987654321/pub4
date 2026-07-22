# frozen_string_literal: true

require_relative "test_helper"

# Hybrid-Norm verdict: deterministic hard signals gate; rubric decides the rest.
class TestVerdict < Minitest::Test
  def test_hard_failure_blocks_regardless_of_rubric
    result = Master::Review::Verdict.new.call(
      deterministic: { parse: true, lint: false }, rubric_score: 0.99,
    )
    refute result.pass?
    assert_includes result.reasons, "failed lint"
  end

  def test_passes_when_deterministic_clean_and_rubric_above_threshold
    result = Master::Review::Verdict.new(rubric_threshold: 0.6).call(
      deterministic: { parse: true, lint: true, tests: true }, rubric_score: 0.8,
    )
    assert result.pass?
    assert_in_delta 0.8, result.score, 0.001
  end

  def test_blocks_when_rubric_below_threshold
    result = Master::Review::Verdict.new(rubric_threshold: 0.6).call(
      deterministic: { parse: true }, rubric_score: 0.4,
    )
    refute result.pass?
  end
end
