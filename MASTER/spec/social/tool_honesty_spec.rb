# frozen_string_literal: true

require "minitest/autorun"

class ToolHonestySpec < Minitest::Test
  CLAIM_RULES = {
    write_success_requires: %w[commit_sha verification_fetch],
    workflow_success_requires: %w[run_id conclusion],
    blocked_write_words: ["blocked", "not landed", "retry", "fallback"],
    missing_ci_words: ["no runs visible", "not verified", "unknown"]
  }.freeze

  def test_write_success_requires_commit_and_verification
    requirements = CLAIM_RULES[:write_success_requires]
    assert_includes requirements, "commit_sha"
    assert_includes requirements, "verification_fetch"
  end

  def test_workflow_green_requires_real_run_conclusion
    requirements = CLAIM_RULES[:workflow_success_requires]
    assert_includes requirements, "run_id"
    assert_includes requirements, "conclusion"
  end

  def test_blocked_writes_must_use_plain_blocker_language
    words = CLAIM_RULES[:blocked_write_words]
    assert_includes words, "blocked"
    assert_includes words, "not landed"
  end

  def test_missing_ci_cannot_be_called_green
    words = CLAIM_RULES[:missing_ci_words]
    assert_includes words, "not verified"
    refute_includes words, "green"
  end
end
