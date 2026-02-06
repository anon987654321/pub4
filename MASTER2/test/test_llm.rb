# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestLLM < Minitest::Test
  def setup
    MASTER::DB.setup(path: ":memory:")
    MASTER::LLM.configure
  end

  def test_rates_defined
    assert MASTER::LLM::RATES.key?("deepseek-r1")
    assert MASTER::LLM::RATES.key?("claude-sonnet-4")
    assert MASTER::LLM::RATES.key?("deepseek-v3")
    assert MASTER::LLM::RATES.key?("gpt-4.1-mini")
    assert MASTER::LLM::RATES.key?("gpt-4.1-nano")
  end

  def test_rate_structure
    rate = MASTER::LLM::RATES["deepseek-r1"]
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

  def test_circuit_available_when_no_failures
    # No failures recorded, should be available
    assert MASTER::LLM.circuit_available?("deepseek-r1")
  end

  def test_circuit_trips_after_threshold
    # Record failures up to threshold
    3.times { MASTER::LLM.record_failure("test-model") }
    
    # Circuit should now be unavailable
    refute MASTER::LLM.circuit_available?("test-model")
  end

  def test_record_cost
    MASTER::LLM.record_cost(model: "deepseek-r1", tokens_in: 1000, tokens_out: 500)
    total = MASTER::DB.get_total_cost
    assert total > 0, "Cost should be recorded"
  end

  def test_remaining_budget
    initial = MASTER::LLM.remaining
    assert_equal MASTER::LLM::BUDGET_LIMIT, initial
    
    MASTER::LLM.record_cost(model: "deepseek-r1", tokens_in: 1000, tokens_out: 500)
    remaining = MASTER::LLM.remaining
    assert remaining < initial, "Remaining budget should decrease"
  end

  def test_affordable_tier
    # With full budget, should select strong
    tier = MASTER::LLM.affordable_tier
    assert_equal :strong, tier
  end

  def test_select_model
    model = MASTER::LLM.select_model
    assert model, "Should select a model"
    assert MASTER::LLM::RATES.key?(model), "Selected model should be in RATES"
  end
end
