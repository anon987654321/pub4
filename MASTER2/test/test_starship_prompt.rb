# frozen_string_literal: true

require_relative "test_helper"

class TestStarshipPrompt < Minitest::Test
  def setup
    setup_db
    # Ensure session exists for prompt tests
    MASTER::Session.start_new
  end

  def test_prompt_is_multi_line
    prompt = MASTER::Pipeline.prompt
    # Starship prompt should be multi-line
    assert prompt.include?("\n"), "Prompt should be multi-line: #{prompt.inspect}"
  end

  def test_prompt_has_info_bar
    prompt = MASTER::Pipeline.prompt
    lines = prompt.split("\n")
    
    # Should have at least 2 lines
    assert lines.length >= 2, "Prompt should have at least 2 lines"
    
    # First line should start with box character
    assert lines[0].start_with?("┌─"), "First line should start with ┌─"
  end

  def test_prompt_has_input_line
    prompt = MASTER::Pipeline.prompt
    lines = prompt.split("\n")
    
    # Last line should be the input line
    assert lines[-1].include?("master"), "Last line should contain 'master'"
    assert lines[-1].include?("»"), "Last line should contain '»' prompt marker"
  end

  def test_prompt_includes_ruby_version
    prompt = MASTER::Pipeline.prompt
    
    # Should include Ruby version in some form
    assert prompt.include?("ruby"), "Prompt should mention ruby"
    assert prompt.include?(RUBY_VERSION.split('.')[0..1].join('.')), 
           "Prompt should include Ruby version"
  end

  def test_prompt_includes_model_info
    prompt = MASTER::Pipeline.prompt
    
    # Should include model emoji or reference
    assert prompt.include?("🤖"), "Prompt should include robot emoji for model"
  end

  def test_prompt_includes_circuit_status
    prompt = MASTER::Pipeline.prompt
    
    # Should include circuit status (ok or tripped)
    assert(prompt.include?("⚡ok") || prompt.include?("⚡tripped"),
           "Prompt should include circuit breaker status")
  end

  def test_prompt_fallback_on_error
    # Simulate an error condition by stubbing a method
    original_method = MASTER::LLM.method(:prompt_model_name)
    
    MASTER::LLM.define_singleton_method(:prompt_model_name) do
      raise "Test error"
    end
    
    prompt = MASTER::Pipeline.prompt
    
    # Should fall back to simple prompt
    assert_equal "master$ ", prompt
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
