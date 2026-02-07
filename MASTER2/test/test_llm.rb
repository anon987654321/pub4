# frozen_string_literal: true

require_relative "test_helper"

class TestLLM < Minitest::Test
  def setup
    setup_db
  end

  def test_models_loaded
    assert MASTER::LLM.models.any?, "Models should be loaded from YAML"
    assert MASTER::LLM.model_rates.key?("deepseek/deepseek-r1")
    assert MASTER::LLM.model_rates.key?("anthropic/claude-sonnet-4")
  end

  def test_rate_structure
    rate = MASTER::LLM.model_rates["deepseek/deepseek-r1"]
    assert rate[:in], "Rate should have :in price"
    assert rate[:out], "Rate should have :out price"
    assert rate[:tier], "Rate should have :tier"
  end

  def test_failures_before_trip
    assert_equal 3, MASTER::LLM::FAILURES_BEFORE_TRIP
  end

  def test_spending_cap
    assert_equal 10.0, MASTER::LLM::SPENDING_CAP
  end

  def test_circuit_closed_when_no_failures
    assert MASTER::LLM.circuit_closed?("deepseek/deepseek-r1")
  end

  def test_budget_remaining
    initial = MASTER::LLM.budget_remaining
    assert_equal MASTER::LLM::SPENDING_CAP, initial
  end

  def test_tier_with_full_budget
    tier = MASTER::LLM.tier
    assert_equal :strong, tier
  end

  def test_select_model
    model = MASTER::LLM.pick
    assert model, "Should pick a model"
    assert model.is_a?(String), "Model should be a string ID"
  end

  def test_record_cost
    cost = MASTER::LLM.record_cost(model: "deepseek/deepseek-r1", tokens_in: 1000, tokens_out: 500)
    assert cost > 0, "Cost should be positive"
    assert MASTER::LLM.budget_remaining < MASTER::LLM::SPENDING_CAP, "Budget should decrease"
  end
end
