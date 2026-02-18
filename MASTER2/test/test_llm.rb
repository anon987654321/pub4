# frozen_string_literal: true

require_relative "test_helper"

class TestLLM < Minitest::Test
  def setup
    setup_db
  end

  def test_models_loaded
    assert MASTER::LLM.models.any?, "Models should be loaded from YAML"
    assert MASTER::LLM.model_rates.key?("deepseek/deepseek-r1")
    # Check for any claude model (version may vary)
    claude_models = MASTER::LLM.model_rates.keys.select { |k| k.include?("claude") }
    assert claude_models.any?, "Should have at least one Claude model"
  end

  def test_rate_structure
    rate = MASTER::LLM.model_rates["deepseek/deepseek-r1"]
    assert rate[:in], "Rate should have :in price"
    assert rate[:out], "Rate should have :out price"
  end

  def test_failures_before_trip
    assert_equal 3, MASTER::CircuitBreaker::FAILURES_BEFORE_TRIP
  end

  def test_spending_cap
    assert_equal Float::INFINITY, MASTER::LLM.spending_cap
  end

  def test_circuit_closed_when_no_failures
    assert MASTER::LLM.circuit_closed?("deepseek/deepseek-r1")
  end

  def test_budget_remaining
    initial = MASTER::LLM.budget_remaining
    assert_equal Float::INFINITY, initial
  end

  def test_tier_with_full_budget
    tier = MASTER::LLM.tier
    assert_equal :strong, tier
  end

  def test_select_model
    model = MASTER::LLM.select_model
    assert model, "Should pick a model"
    assert model.is_a?(String), "Model should be a string ID"
  end

  def test_record_cost
    cost = MASTER::LLM.record_cost(model: "deepseek/deepseek-r1", tokens_in: 1000, tokens_out: 500)
    assert_equal 0.0, cost, "Cost should be 0.0 (budget tracking removed)"
    assert_equal Float::INFINITY, MASTER::LLM.budget_remaining, "Budget should remain infinity"
  end

  def test_force_model
    test_model = "deepseek/deepseek-r1"
    MASTER::LLM.force_model!(test_model)
    
    assert MASTER::LLM.model_forced?, "Model should be marked as forced"
    assert_equal test_model, MASTER::LLM.forced_model, "Forced model should be set"
    assert_equal :fast, MASTER::LLM.forced_tier, "Forced tier should be classified"
  end

  def test_clear_forced_model
    test_model = "deepseek/deepseek-r1"
    MASTER::LLM.force_model!(test_model)
    assert MASTER::LLM.model_forced?, "Model should be forced before clearing"
    
    MASTER::LLM.clear_forced_model!
    
    refute MASTER::LLM.model_forced?, "Model should not be forced after clearing"
    assert_nil MASTER::LLM.forced_model, "Forced model should be nil"
    assert_nil MASTER::LLM.forced_tier, "Forced tier should be nil"
  end

  def test_model_forced_returns_correct_value
    refute MASTER::LLM.model_forced?, "Model should not be forced initially"
    
    MASTER::LLM.force_model!("deepseek/deepseek-r1")
    assert MASTER::LLM.model_forced?, "Model should be forced after force_model!"
  end
end
