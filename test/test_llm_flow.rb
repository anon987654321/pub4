# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestLLMFlow < Minitest::Test
  # Model tier tests
  def test_tier_order_exists
    assert_equal %i[strong fast cheap], MASTER::LLM::TIER_ORDER
  end

  def test_model_tiers_hash_exists
    tiers = MASTER::LLM.model_tiers
    assert tiers.is_a?(Hash)
    assert tiers.key?(:strong) || tiers.key?(:fast) || tiers.key?(:cheap)
  end

  def test_pick_returns_model
    model = MASTER::LLM.pick
    # Should return a string or nil
    assert model.nil? || model.is_a?(String)
  end

  def test_pick_with_tier
    model = MASTER::LLM.pick(:fast)
    assert model.nil? || model.is_a?(String)
  end

  # Budget tracking
  def test_budget_remaining_returns_number
    budget = MASTER::LLM.budget_remaining
    assert budget.is_a?(Numeric)
    assert budget >= 0
  end

  def test_spending_cap_exists
    assert MASTER::LLM::SPENDING_CAP.is_a?(Numeric)
    assert MASTER::LLM::SPENDING_CAP > 0
  end

  # Circuit breaker
  def test_circuit_closed_returns_boolean
    model = MASTER::LLM.model_tiers[:fast]&.first || "test/model"
    result = MASTER::LLM.circuit_closed?(model)
    assert [true, false].include?(result)
  end

  # Model name extraction
  def test_extract_model_name_full_path
    name = MASTER::LLM.extract_model_name("anthropic/claude-3-opus")
    assert_equal "claude-3-opus", name
  end

  def test_extract_model_name_with_suffix
    name = MASTER::LLM.extract_model_name("openai/gpt-4:online")
    assert_equal "gpt-4", name
  end

  def test_extract_model_name_simple
    name = MASTER::LLM.extract_model_name("gpt-4")
    assert_equal "gpt-4", name
  end

  # Configuration check
  def test_configured_returns_boolean
    result = MASTER::LLM.configured?
    assert [true, false].include?(result)
  end

  # Ask method exists
  def test_ask_method_exists
    assert MASTER::LLM.respond_to?(:ask)
  end

  def test_ask_returns_result_without_key
    # Without API key, should return error Result
    original_key = ENV["OPENROUTER_API_KEY"]
    ENV["OPENROUTER_API_KEY"] = nil

    result = MASTER::LLM.ask("test prompt")
    assert result.respond_to?(:ok?)
    # Should be error since no key
    if !MASTER::LLM.configured?
      assert result.err?
    end

    ENV["OPENROUTER_API_KEY"] = original_key
  end

  # JSON and reasoning variants
  def test_ask_json_method_exists
    assert MASTER::LLM.respond_to?(:ask_json)
  end

  def test_ask_with_reasoning_method_exists
    assert MASTER::LLM.respond_to?(:ask_with_reasoning)
  end

  # Tier is computed from budget, not settable
  def test_tier_returns_symbol
    tier = MASTER::LLM.tier
    assert %i[strong fast cheap].include?(tier)
  end

  # Current model tracking
  def test_current_model_accessor
    MASTER::LLM.current_model = "test-model"
    assert_equal "test-model", MASTER::LLM.current_model
    MASTER::LLM.current_model = nil
  end

  def test_current_tier_accessor
    MASTER::LLM.current_tier = :strong
    assert_equal :strong, MASTER::LLM.current_tier
    MASTER::LLM.current_tier = nil
  end

  # Prompt display
  def test_prompt_model_name
    MASTER::LLM.current_model = "gpt-4"
    name = MASTER::LLM.prompt_model_name
    assert name.is_a?(String)
    MASTER::LLM.current_model = nil
  end
end
