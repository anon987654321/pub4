# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestHooks < Minitest::Test
  def test_config_loads
    config = MASTER::Hooks.config
    assert_kind_of Hash, config
  end

  def test_before_edit_hooks_exist
    config = MASTER::Hooks.config
    assert config["before_edit"], "before_edit hooks should exist"
    assert_includes config["before_edit"], "backup_original"
  end

  def test_on_stuck_hooks_exist
    config = MASTER::Hooks.config
    assert config["on_stuck"], "on_stuck hooks should exist"
    assert_includes config["on_stuck"], "escalate_to_user"
  end

  def test_run_returns_results
    results = MASTER::Hooks.run(:before_edit, {})
    assert_kind_of Array, results
  end
end

class TestConvergence < Minitest::Test
  def test_empty_history
    result = MASTER::Convergence.track([], { violations: 10 })
    assert_equal 1, result[:iteration]
    refute result[:should_stop]
  end

  def test_plateau_detection
    history = [
      { violations: 5, score: 95 },
      { violations: 5, score: 95 },
      { violations: 5, score: 95 },
    ]
    result = MASTER::Convergence.track(history, { violations: 5, score: 95 })
    assert result[:plateau], "Should detect plateau"
  end

  def test_convergence_at_zero_violations
    history = [{ violations: 1 }]
    result = MASTER::Convergence.track(history, { violations: 0 })
    assert result[:should_stop]
    assert_equal :converged, result[:reason]
  end

  def test_oscillation_detection
    history = [
      { score: 90 },
      { score: 80 },
      { score: 90 },
      { score: 80 },
    ]
    assert MASTER::Convergence.oscillating?(history)
  end

  def test_summary
    history = [
      { violations: 10 },
      { violations: 5 },
      { violations: 2 },
    ]
    summary = MASTER::Convergence.summary(history)
    assert_includes summary, "3 iterations"
    assert_includes summary, "80.0% improvement"
  end
end

class TestQuestions < Minitest::Test
  def test_config_loads
    config = MASTER::Questions.config
    assert_kind_of Hash, config
  end

  def test_phases_exist
    MASTER::Questions::PHASES.each do |phase|
      info = MASTER::Questions.for_phase(phase)
      assert info[:purpose], "#{phase} should have purpose"
      assert_kind_of Array, info[:questions]
      assert info[:questions].size >= 5, "#{phase} should have at least 5 questions"
    end
  end

  def test_phases_for_bug_fix
    phases = MASTER::Questions.phases_for_type(:bug_fix)
    assert_equal %i[analyze implement validate deliver], phases
  end

  def test_prompt_generation
    prompt = MASTER::Questions.prompt_for_phase(:discover, "test context")
    assert_includes prompt, "DISCOVER"
    assert_includes prompt, "What specifically is the problem?"
    assert_includes prompt, "test context"
  end
end
