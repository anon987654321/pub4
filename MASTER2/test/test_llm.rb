# frozen_string_literal: true

require_relative "test_helper"

class TestLLM < Minitest::Test
  def setup
    setup_db
  end

  def test_rates_defined
    assert MASTER::LLM::RATES.key?("deepseek/deepseek-r1")
    assert MASTER::LLM::RATES.key?("anthropic/claude-sonnet-4")
  end

  def test_rate_structure
    rate = MASTER::LLM::RATES["deepseek/deepseek-r1"]
    assert rate[:in], "Rate should have :in price"
    assert rate[:out], "Rate should have :out price"
    assert rate[:tier], "Rate should have :tier"
  end

  def test_circuit_threshold
    assert_equal 3, MASTER::LLM::CIRCUIT_THRESHOLD
  end

  def test_budget_limit
    assert_equal 10.0, MASTER::LLM::BUDGET_LIMIT
  end

  def test_healthy_when_no_failures
    assert MASTER::LLM.healthy?("deepseek/deepseek-r1")
  end

  def test_remaining_budget
    initial = MASTER::LLM.remaining
    assert_equal MASTER::LLM::BUDGET_LIMIT, initial
  end

  def test_tier_with_full_budget
    tier = MASTER::LLM.tier
    assert_equal :strong, tier
  end

  def test_select_model
    result = MASTER::LLM.select_model(500)
    assert result, "Should select a model"
    assert result[:model], "Should have model key"
    assert result[:tier], "Should have tier key"
  end

  def test_record_cost
    cost = MASTER::LLM.record_cost(model: "deepseek/deepseek-r1", tokens_in: 1000, tokens_out: 500)
    assert cost > 0, "Cost should be positive"
    assert MASTER::LLM.remaining < MASTER::LLM::BUDGET_LIMIT, "Budget should decrease"
  end
end
