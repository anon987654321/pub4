# frozen_string_literal: true

require_relative "test_helper"

class TestExecutorPatterns < Minitest::Test
  def setup
    setup_db
    stub_llm_ask(content: "ANSWER: The answer is 42")
  end

  def teardown
    restore_llm_ask
    teardown_db
  end

  def test_direct_pattern_returns_ok
    executor = MASTER::Executor.new
    # Force direct pattern to bypass executor loop
    result = executor.call("hi", pattern: :direct)
    assert result.ok?, "Direct pattern should return ok, got: #{result.error}"
  end

  def test_direct_pattern_includes_answer
    executor = MASTER::Executor.new
    result = executor.call("hello there", pattern: :direct)
    assert result.ok?
    assert result.value[:answer] || result.value[:content], "Should have answer or content"
  end

  def test_direct_pattern_metadata
    executor = MASTER::Executor.new
    result = executor.call("what is ruby?", pattern: :direct)
    assert result.ok?
    assert_equal 0, result.value[:steps]
    assert_equal :direct, result.value[:pattern]
  end

  def test_react_pattern_completes
    stub_llm_ask(content: "ANSWER: React completed successfully")
    executor = MASTER::Executor.new(max_steps: 3)
    result = executor.call("test task", pattern: :react)
    assert result.respond_to?(:ok?), "Should return a Result"
  end

  def test_executor_with_auto_pattern
    executor = MASTER::Executor.new(max_steps: 3)
    result = executor.call("What is 2+2?", pattern: :auto)
    assert result.respond_to?(:ok?), "Auto pattern should return a Result"
  end

  def test_executor_handles_llm_failure
    stub_llm_ask_failure(error: "All models down")
    executor = MASTER::Executor.new(max_steps: 2)
    result = executor.call("do something", pattern: :direct)
    assert result.err?, "Should return error when LLM fails"
  end

  def test_executor_class_method_call
    result = MASTER::Executor.call("hi", pattern: :direct)
    assert result.respond_to?(:ok?), "Class method should return a Result"
  end
end
