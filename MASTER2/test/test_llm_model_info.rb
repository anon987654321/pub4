# frozen_string_literal: true

require_relative "test_helper"

# Test for ruby_llm v1.11.0 compatibility with RubyLLM::Model::Info objects
class TestLLMModelInfo < Minitest::Test
  # Simple struct to simulate RubyLLM::Model::Info for testing
  class MockModel
    attr_reader :id, :input_price_per_million, :output_price_per_million, :context_window
    
    def initialize(id:, input_price_per_million:, output_price_per_million: 1.0, context_window: 32_000)
      @id = id
      @input_price_per_million = input_price_per_million
      @output_price_per_million = output_price_per_million
      @context_window = context_window
    end
  end

  def setup
    setup_db
    # Clear any cached values
    MASTER::LLM.instance_variable_set(:@model_tiers, nil)
    MASTER::LLM.instance_variable_set(:@model_rates, nil)
    MASTER::LLM.instance_variable_set(:@context_limits, nil)
  end

  def test_classify_tier_premium
    # Model with premium pricing (>= 10.0)
    model = MockModel.new(id: "premium-model", input_price_per_million: 15.0)
    
    tier = MASTER::LLM.classify_tier(model)
    assert_equal :premium, tier
  end

  def test_classify_tier_strong
    # Model with strong pricing (>= 2.0, < 10.0)
    model = MockModel.new(id: "strong-model", input_price_per_million: 5.0)
    
    tier = MASTER::LLM.classify_tier(model)
    assert_equal :strong, tier
  end

  def test_classify_tier_fast
    # Model with fast pricing (>= 0.1, < 2.0)
    model = MockModel.new(id: "fast-model", input_price_per_million: 0.5)
    
    tier = MASTER::LLM.classify_tier(model)
    assert_equal :fast, tier
  end

  def test_classify_tier_cheap
    # Model with cheap pricing (< 0.1)
    model = MockModel.new(id: "cheap-model", input_price_per_million: 0.01)
    
    tier = MASTER::LLM.classify_tier(model)
    assert_equal :cheap, tier
  end

  def test_classify_tier_nil_price
    # Model with nil pricing (should default to 0 = cheap)
    model = MockModel.new(id: "nil-model", input_price_per_million: nil)
    
    tier = MASTER::LLM.classify_tier(model)
    assert_equal :cheap, tier
  end

  def test_model_tiers_uses_object_accessors
    # Skip if API key not configured (models might not be available)
    skip "API key required" unless MASTER::LLM.configured?
    
    # Ensure RubyLLM is configured
    MASTER::LLM.configure_ruby_llm
    
    # This should not raise an error about undefined method []
    tiers = MASTER::LLM.model_tiers
    
    # Verify it returns a hash with tier keys
    assert_kind_of Hash, tiers
    assert_includes tiers.keys, :premium
    assert_includes tiers.keys, :strong
    assert_includes tiers.keys, :fast
    assert_includes tiers.keys, :cheap
    
    # Each tier should map to an array of model IDs (strings)
    tiers.each do |tier, models|
      assert_kind_of Array, models
      models.each do |model_id|
        assert_kind_of String, model_id
      end
    end
  end

  def test_model_rates_uses_object_accessors
    # Skip if API key not configured
    skip "API key required" unless MASTER::LLM.configured?
    
    # Ensure RubyLLM is configured
    MASTER::LLM.configure_ruby_llm
    
    # This should not raise an error about undefined method []
    rates = MASTER::LLM.model_rates
    
    # Verify it returns a hash
    assert_kind_of Hash, rates
    
    # Check structure of at least one entry (if any models exist)
    unless rates.empty?
      model_id, rate_info = rates.first
      assert_kind_of String, model_id
      assert_kind_of Hash, rate_info
      assert_includes rate_info.keys, :in
      assert_includes rate_info.keys, :out
      assert_includes rate_info.keys, :tier
      assert_kind_of Numeric, rate_info[:in]
      assert_kind_of Numeric, rate_info[:out]
      assert_kind_of Symbol, rate_info[:tier]
    end
  end

  def test_context_limits_uses_object_accessors
    # Skip if API key not configured
    skip "API key required" unless MASTER::LLM.configured?
    
    # Ensure RubyLLM is configured
    MASTER::LLM.configure_ruby_llm
    
    # This should not raise an error about undefined method []
    limits = MASTER::LLM.context_limits
    
    # Verify it returns a hash
    assert_kind_of Hash, limits
    
    # Check structure of at least one entry (if any models exist)
    unless limits.empty?
      model_id, limit = limits.first
      assert_kind_of String, model_id
      assert_kind_of Integer, limit
      assert limit > 0, "Context limit should be positive"
    end
  end
end
