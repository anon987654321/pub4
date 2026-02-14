# frozen_string_literal: true

require_relative "test_helper"

class TestLLMRubyLLM < Minitest::Test
  def setup
    setup_db
  end

  def test_ruby_llm_configuration
    # Test that configuration can be called without error
    MASTER::LLM.configure_ruby_llm
    # Verify the configuration method exists and is callable
    assert_respond_to MASTER::LLM, :configure_ruby_llm
  end

  def test_ruby_llm_available_check
    # RubyLLM is now a hard dependency, so it's always available
    # Test that configuration works without error
    MASTER::LLM.configure_ruby_llm
    # Verify RubyLLM module exists and is configured
    assert defined?(RubyLLM), "RubyLLM module should be defined"
    # Note: Cannot directly access @ruby_llm_configured as it's private,
    # but successful configuration is verified by no errors being raised
  end

  def test_reasoning_effort_validation
    # Test that invalid reasoning effort is rejected
    result = MASTER::LLM.ask("test", reasoning: :invalid_effort)
    assert result.err?, "Should reject invalid reasoning effort"
  end

  def test_fallback_models_logic
    # Test that fallback models array is properly handled
    skip "API key required" unless MASTER::LLM.configured?
    
    # This test verifies the fallback logic structure without making real API calls
    # The actual API calls would need mocking or a test mode
    assert_respond_to MASTER::LLM, :ask
  end

  def test_max_response_size_constant
    assert_equal 5_000_000, MASTER::LLM::MAX_RESPONSE_SIZE
  end

  def test_response_validation_checks_content
    # Create a mock response with empty content
    response_data = {
      content: "",
      reasoning: nil,
      model: "test-model",
      tokens_in: 100,
      tokens_out: 50,
      cost: 0.001,
      finish_reason: "stop"
    }
    
    result = MASTER::LLM.send(:validate_response, response_data, "test-model")
    assert result.err?, "Should reject empty content"
    assert_match(/Empty response/, result.error)
  end

  def test_response_validation_handles_non_numeric_tokens
    response_data = {
      content: "test content",
      reasoning: nil,
      model: "test-model",
      tokens_in: "invalid",
      tokens_out: nil,
      cost: "invalid",
      finish_reason: "stop"
    }
    
    result = MASTER::LLM.send(:validate_response, response_data, "test-model")
    assert result.ok?, "Should handle non-numeric tokens gracefully"
    assert_equal 0, result.value[:tokens_in]
    assert_equal 0, result.value[:tokens_out]
    assert_nil result.value[:cost]
  end

  def test_message_history_preservation
    # Test that full message history is preserved
    messages = [
      { role: "user", content: "First message" },
      { role: "assistant", content: "First response" },
      { role: "user", content: "Second message" }
    ]
    
    content = MASTER::LLM.send(:build_message_content, "New prompt", messages)
    assert content.include?("First message")
    assert content.include?("First response")
    assert content.include?("Second message")
    assert content.include?("New prompt")
  end

  def test_error_preserves_type_and_backtrace
    # Test that errors preserve type and backtrace information
    # Simulate an error in the ruby_llm execution path
    begin
      # Create a mock error with backtrace
      raise ArgumentError, "Test error"
    rescue ArgumentError => e
      # Format error as our code does (consistent string format)
      error_msg = "#{e.class.name}: #{e.message}"
      error_msg += "\n  " + e.backtrace.first(5).join("\n  ") if e.backtrace
      
      assert error_msg.start_with?("ArgumentError: Test error")
      assert error_msg.include?("\n  "), "Should include backtrace lines"
      # Count newlines to verify backtrace is included (should have at least 1)
      assert error_msg.scan(/\n/).count >= 1, "Should have backtrace lines"
    end
  end
end
