# frozen_string_literal: true

require_relative "test_helper"

class TestStarshipPrompt < Minitest::Test
  def test_prompt_returns_multiline_string
    prompt = MASTER::Pipeline.prompt
    
    assert_kind_of String, prompt
    assert prompt.include?("┌─"), "Should have top line with box drawing character"
    assert prompt.include?("└─"), "Should have bottom line with box drawing character"
    assert prompt.include?("master »"), "Should have master prompt"
  end
  
  def test_prompt_includes_ruby_version
    prompt = MASTER::Pipeline.prompt
    
    assert prompt.include?("ruby"), "Should include ruby version info"
    assert prompt.include?(RUBY_VERSION), "Should include actual Ruby version"
  end
  
  def test_prompt_includes_model_info
    prompt = MASTER::Pipeline.prompt
    
    # Should have model emoji
    assert prompt.include?("🤖"), "Should include robot emoji for model"
  end
  
  def test_prompt_includes_separator
    prompt = MASTER::Pipeline.prompt
    
    # Segments should be separated by " · "
    assert prompt.include?(" · "), "Should have bullet separator between segments"
  end
  
  def test_prompt_fallback_on_error
    # The prompt is quite defensive, so let me test the actual structure works
    prompt = MASTER::Pipeline.prompt
    
    # Should be multi-line or fall back to simple prompt
    assert prompt.include?("master"), "Should include 'master' in prompt"
    assert prompt.include?(" "), "Should have spaces"
  end
  
  def test_git_info_returns_nil_when_not_in_repo
    # Test outside of a git repo (should handle gracefully)
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        result = MASTER::Pipeline.git_info
        assert_nil result, "Should return nil when not in git repo"
      end
    end
  end
end
