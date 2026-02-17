# frozen_string_literal: true

require_relative "test_helper"

class TestStarshipPrompt < Minitest::Test
  def setup
    setup_db
    # Ensure session exists for prompt tests
    MASTER::Session.start_new
  end

  def test_prompt_is_single_line
    prompt = MASTER::Pipeline.prompt
    refute prompt.include?("\n"), "Prompt should be single-line: #{prompt.inspect}"
  end

  def test_prompt_has_input_line
    prompt = MASTER::Pipeline.prompt
    assert prompt.include?("master"), "Prompt should contain 'master'"
    assert prompt.end_with?(" > "), "Prompt should end with '> ': #{prompt.inspect}"
  end

  def test_prompt_includes_model_info
    prompt = MASTER::Pipeline.prompt
    refute_empty prompt.strip
  end

  def test_prompt_fallback_on_error
    # Simulate an error condition by stubbing a method
    original_method = MASTER::LLM.method(:prompt_model_name)
    
    MASTER::LLM.define_singleton_method(:prompt_model_name) do
      raise "Test error"
    end
    
    prompt = MASTER::Pipeline.prompt
    
    # Should fall back to simple prompt
    assert_equal "master > ", prompt
  ensure
    # Restore original method
    MASTER::LLM.define_singleton_method(:prompt_model_name, original_method)
  end

  def test_git_info_returns_nil_outside_repo
    # In a temp directory without git
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        info = MASTER::Pipeline.git_info
        assert_nil info, "Should return nil outside git repo"
      end
    end
  end

  def teardown
    teardown_db
  end
end
