#!/usr/bin/env ruby
# frozen_string_literal: true

# CONVERGENCE CLI Test Suite
# Run: ruby cli_test.rb

require "minitest/autorun"
require_relative "cli"

class MasterConfigTest < Minitest::Test
  def setup
    @config = MasterConfig.new
  end

  def test_version_loaded
    refute_nil @config.version
  end

  def test_preferred_tools_loaded
    assert @config.preferred_tools.include?("ruby")
    assert @config.preferred_tools.include?("zsh")
    assert @config.preferred_tools.include?("doas")
  end

  def test_preferred_detection
    assert @config.preferred?("ruby script.rb")
    assert @config.preferred?("zsh -c 'echo hello'")
    refute @config.preferred?("python script.py")
  end
end

class ConfigTest < Minitest::Test
  def test_default_provider
    config = Config.new
    assert_equal :openrouter, config.provider
  end

  def test_configured_check
    config = Config.new
    refute config.configured?
    
    config.api_key = "test-key"
    config.provider = :openrouter
    assert config.configured?
  end
end

class APIClientTest < Minitest::Test
  def test_providers_defined
    assert APIClient::PROVIDERS.key?(:openrouter)
  end

  def test_openrouter_models
    models = APIClient::PROVIDERS[:openrouter][:models]
    assert models.key?("deepseek-r1")
    assert models.key?("claude-3.5")
    assert models.key?("gpt-4o")
  end

  def test_default_model
    default = APIClient::PROVIDERS[:openrouter][:default_model]
    assert_equal "deepseek/deepseek-r1", default
  end
end

class DirectoryProcessorTest < Minitest::Test
  def test_processable_extensions
    processor = DirectoryProcessor.new(Dir.pwd, MasterConfig.new)
    
    # Test via reflection since processable? is private
    assert processor.send(:processable?, "test.rb")
    assert processor.send(:processable?, "test.sh")
    assert processor.send(:processable?, "test.yml")
    refute processor.send(:processable?, "test.exe")
    refute processor.send(:processable?, "test.jpg")
  end
end

class ShellToolTest < Minitest::Test
  def setup
    @tool = ShellTool.new
  end

  def test_execute_simple_command
    result = @tool.execute(command: "echo hello")
    assert result[:success]
    assert_includes result[:stdout], "hello"
  end

  def test_timeout_handling
    # Very short timeout should fail for sleep
    result = @tool.execute(command: "sleep 5", timeout: 1)
    assert result[:error]
    assert_includes result[:error], "timeout"
  end
end

class FileToolTest < Minitest::Test
  def setup
    @tool = FileTool.new(base_path: Dir.pwd)
  end

  def test_read_existing_file
    # cli.rb should exist
    result = @tool.read(path: "cli.rb")
    refute result[:error]
    assert result[:content]
    assert result[:size] > 0
  end

  def test_sandbox_enforcement
    # Should block access outside base_path
    result = @tool.read(path: "/etc/passwd")
    assert result[:error]
    assert_includes result[:error].to_s.downcase, "denied"
  end
end

class SessionManagerTest < Minitest::Test
  def setup
    @mgr = SessionManager.new
  end

  def test_save_and_load_session
    test_state = { "test" => true, "created_at" => Time.now.to_i }
    @mgr.save("test_session", test_state)
    
    loaded = @mgr.load("test_session")
    assert_equal true, loaded["test"]
    
    # Cleanup
    File.delete(File.join(SessionManager::SESSION_DIR, "test_session.yml")) rescue nil
  end

  def test_list_sessions
    sessions = @mgr.list
    assert sessions.is_a?(Array)
  end
end

# Run if executed directly
if __FILE__ == $PROGRAM_NAME
  puts "Running CONVERGENCE CLI tests..."
  puts "=" * 50
end
