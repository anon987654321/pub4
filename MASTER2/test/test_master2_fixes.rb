# frozen_string_literal: true

require_relative "test_helper"

class TestMaster2Fixes < Minitest::Test
  def setup
    setup_db
  end

  # Test Part 1: Logic Bug Fixes

  def test_retryable_error_detection
    # Test that retryable_error? correctly uses regex, not string literal
    assert MASTER::LLM.send(:retryable_error?, "Connection timeout")
    assert MASTER::LLM.send(:retryable_error?, "Network error: 503")
    assert MASTER::LLM.send(:retryable_error?, "Rate limit: 429")
    assert MASTER::LLM.send(:retryable_error?, "Service overloaded")
    refute MASTER::LLM.send(:retryable_error?, "Invalid API key")
    refute MASTER::LLM.send(:retryable_error?, "Model not found")
  end

  def test_tier_includes_premium
    # Mock budget_remaining to test premium tier
    MASTER::LLM.instance_variable_set(:@budget_thresholds, { premium: 8.0, strong: 5.0, fast: 1.0 })
    
    # Test premium tier (budget > 8.0)
    MASTER::LLM.stub :budget_remaining, 9.0 do
      assert_equal :premium, MASTER::LLM.tier
    end
    
    # Test strong tier (5.0 < budget <= 8.0)
    MASTER::LLM.stub :budget_remaining, 6.0 do
      assert_equal :strong, MASTER::LLM.tier
    end
    
    # Test fast tier (1.0 < budget <= 5.0)
    MASTER::LLM.stub :budget_remaining, 2.0 do
      assert_equal :fast, MASTER::LLM.tier
    end
    
    # Test cheap tier (budget <= 1.0)
    MASTER::LLM.stub :budget_remaining, 0.5 do
      assert_equal :cheap, MASTER::LLM.tier
    end
  ensure
    MASTER::LLM.instance_variable_set(:@budget_thresholds, nil)
  end

  def test_estimate_cost_by_model
    # Test the new explicit method
    model = "deepseek/deepseek-r1"
    cost = MASTER::LLM.estimate_cost_by_model(model, tokens_in: 1000, tokens_out: 500)
    assert cost > 0, "Cost should be positive"
    assert cost.is_a?(Float), "Cost should be a Float"
  end

  def test_estimate_cost_by_chars
    # Test the new explicit method for character-based estimation
    model = "deepseek/deepseek-r1"
    cost = MASTER::LLM.estimate_cost_by_chars(4000, model)
    assert cost > 0, "Cost should be positive"
    assert cost.is_a?(Float), "Cost should be a Float"
  end

  # Test Part 3: Dangerous Patterns Consolidation

  def test_dangerous_patterns_loaded
    patterns = MASTER::DangerousPatterns.patterns
    assert patterns.any?, "Should load patterns from YAML"
    assert patterns.all? { |p| p[:name] && p[:regex] && p[:description] }, "Patterns should have required fields"
  end

  def test_dangerous_patterns_detection
    assert MASTER::DangerousPatterns.dangerous?("rm -rf /")
    assert MASTER::DangerousPatterns.dangerous?("cat file > /dev/sda")
    assert MASTER::DangerousPatterns.dangerous?("DROP TABLE users")
    assert MASTER::DangerousPatterns.dangerous?("FORMAT C:")
    assert MASTER::DangerousPatterns.dangerous?("mkfs.ext4 /dev/sda1")
    assert MASTER::DangerousPatterns.dangerous?("dd if=/dev/zero of=/dev/sda")
    
    refute MASTER::DangerousPatterns.dangerous?("ls -la /home/user")
    refute MASTER::DangerousPatterns.dangerous?("rm file.txt")
    refute MASTER::DangerousPatterns.dangerous?("SELECT * FROM users")
  end

  def test_dangerous_patterns_check_details
    result = MASTER::DangerousPatterns.check("rm -rf /")
    assert result[:dangerous], "Should detect as dangerous"
    assert result[:pattern], "Should return pattern name"
    assert result[:description], "Should return description"
    
    result = MASTER::DangerousPatterns.check("ls -la")
    refute result[:dangerous], "Should not detect as dangerous"
  end

  # Test Part 5: Classifier

  def test_classifier_pattern_selection_fallback
    # Test regex fallback (when LLM is unavailable)
    MASTER::LLM.stub :configured?, false do
      assert_equal "pre_act", MASTER::Classifier.classify(:pattern_selection, "First build the API, then deploy it")
      assert_equal "pre_act", MASTER::Classifier.classify(:pattern_selection, "Create and implement a new feature")
      assert_equal "rewoo", MASTER::Classifier.classify(:pattern_selection, "Explain how REST APIs work")
      assert_equal "reflexion", MASTER::Classifier.classify(:pattern_selection, "Fix the broken login function")
      assert_equal "reflexion", MASTER::Classifier.classify(:pattern_selection, "Debug this carefully without breaking it")
      assert_equal "react", MASTER::Classifier.classify(:pattern_selection, "List all files in the directory")
    end
  end

  def test_classifier_query_complexity_fallback
    # Test regex fallback (when LLM is unavailable)
    MASTER::LLM.stub :configured?, false do
      assert_equal "simple", MASTER::Classifier.classify(:query_complexity, "What is Ruby?")
      assert_equal "simple", MASTER::Classifier.classify(:query_complexity, "Hello")
      assert_equal "complex", MASTER::Classifier.classify(:query_complexity, "Read all files in src/ and analyze them")
      assert_equal "complex", MASTER::Classifier.classify(:query_complexity, "Fix the authentication bug")
    end
  end

  def test_classifier_default_fallback
    # Test that unknown inputs get default category
    MASTER::LLM.stub :configured?, false do
      result = MASTER::Classifier.classify(:pattern_selection, "xyz123unknown")
      assert_equal "react", result, "Should return default for unknown input"
    end
  end
end
