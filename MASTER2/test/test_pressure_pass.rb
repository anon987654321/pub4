# frozen_string_literal: true

require_relative "test_helper"

class TestPressurePass < Minitest::Test
  def test_prompt_includes_full_crit_session_panel
    prompt = MASTER::PressurePass.prompt("Improve this answer", "Candidate")

    assert_includes prompt, "adversarial architect"
    assert_includes prompt, "adversarial web designer"
    assert_includes prompt, "adversarial electronic musician"
    assert_includes prompt, "adversarial indie filmmaker"
    assert_includes prompt, "adversarial slam poet"
  end

  def test_prompt_enforces_cherry_picked_multi_solution_selection
    prompt = MASTER::PressurePass.prompt("Request", "Candidate")

    assert_includes prompt, "Cherry-pick the strongest parts across alternatives"
    assert_includes prompt, "Ask adversarial questions before proposing alternatives"
  end
end
