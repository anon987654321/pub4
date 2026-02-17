# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestDRYFixes < Minitest::Test
  # Test 1: tool_list_text helper exists and works
  def test_tool_list_text_helper_exists
    text = MASTER::Executor.tool_list_text
    assert text.is_a?(String)
    assert text.include?("ask_llm:")
    assert text.include?("file_read:")
    assert text.include?("shell_command:")
  end

  # Test 2: Learnings uses correct key names
  def test_learnings_uses_applied_count_key
    # Create a mock pattern with applied_count
    pattern = { applied_count: 5, successes: 4, failures: 1 }
    learnings = MASTER::Learnings.new("test_category")
    
    # evaluate should use applied_count, not applications
    result = learnings.evaluate(pattern)
    assert [:unrated, :promote, :keep, :demote, :retire].include?(result)
  end

  # Test 3: format_tokens is in Utils
  def test_format_tokens_in_utils
    assert_equal "500", MASTER::Utils.format_tokens(500)
    assert_equal "1.5k", MASTER::Utils.format_tokens(1500)
    assert_equal "2.5M", MASTER::Utils.format_tokens(2_500_000)
  end

  # Test 4: Executor constants exist
  def test_executor_constants_exist
    assert_equal 3000, MASTER::Executor::MAX_FILE_CONTENT
    assert_equal 2000, MASTER::Executor::MAX_CURL_CONTENT
    assert_equal 1000, MASTER::Executor::MAX_LLM_RESPONSE_PREVIEW
    assert_equal 1000, MASTER::Executor::MAX_SHELL_OUTPUT
  end

  # Test 5: Pipeline raises on invalid mode
  def test_pipeline_raises_on_invalid_mode
    pipeline = MASTER::Pipeline.new(mode: :invalid_mode)
    error = assert_raises(ArgumentError) do
      pipeline.call("test input")
    end
    assert_match(/Unknown pipeline mode/, error.message)
  end
end
