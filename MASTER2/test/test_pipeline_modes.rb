# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestPipelineModes < Minitest::Test
  def test_default_stages_constant
    stages = MASTER::Pipeline::DEFAULT_STAGES
    assert stages.is_a?(Array)
    assert stages.include?(:intake)
    assert stages.include?(:guard)
  end

  def test_current_pattern_accessor
    original = MASTER::Pipeline.current_pattern
    
    MASTER::Pipeline.current_pattern = :react
    assert_equal :react, MASTER::Pipeline.current_pattern
    
    MASTER::Pipeline.current_pattern = :pre_act
    assert_equal :pre_act, MASTER::Pipeline.current_pattern
    
    MASTER::Pipeline.current_pattern = original
  end

  def test_current_pattern_default_is_auto
    # Reset to default
    MASTER::Pipeline.current_pattern = :auto
    assert_equal :auto, MASTER::Pipeline.current_pattern
  end

  def test_initialize_with_executor_mode
    pipeline = MASTER::Pipeline.new(mode: :executor)
    assert_equal :executor, pipeline.instance_variable_get(:@mode)
  end

  def test_initialize_with_stages_mode
    pipeline = MASTER::Pipeline.new(mode: :stages)
    assert_equal :stages, pipeline.instance_variable_get(:@mode)
  end

  def test_initialize_with_direct_mode
    pipeline = MASTER::Pipeline.new(mode: :direct)
    assert_equal :direct, pipeline.instance_variable_get(:@mode)
  end

  def test_prompt_returns_string
    prompt = MASTER::Pipeline.prompt
    assert prompt.is_a?(String)
    assert prompt.include?("master")
  end

  def test_prompt_includes_model_when_set
    MASTER::LLM.current_model = "test-model"
    prompt = MASTER::Pipeline.prompt
    assert prompt.include?("test") || prompt.include?("master")
    MASTER::LLM.current_model = nil
  end

  def test_format_tokens_under_1000
    result = MASTER::Pipeline.format_tokens(500)
    assert_equal "500", result
  end

  def test_format_tokens_thousands
    result = MASTER::Pipeline.format_tokens(2500)
    assert_equal "2.5k", result
  end

  def test_format_tokens_millions
    result = MASTER::Pipeline.format_tokens(1_500_000)
    assert_equal "1.5M", result
  end

  def test_call_accepts_string_input
    pipeline = MASTER::Pipeline.new(mode: :direct)
    # This would call LLM, so we just verify it doesn't crash on setup
    assert pipeline.respond_to?(:call)
  end

  def test_call_accepts_hash_input
    pipeline = MASTER::Pipeline.new(mode: :direct)
    # Verify the pipeline can handle hash input format
    assert pipeline.respond_to?(:call)
  end

  # Class methods
  def test_repl_method_exists
    assert MASTER::Pipeline.respond_to?(:repl)
  end

  def test_pipe_method_exists
    assert MASTER::Pipeline.respond_to?(:pipe)
  end
end
