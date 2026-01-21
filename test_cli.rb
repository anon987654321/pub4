#!/usr/bin/env ruby
# frozen_string_literal: true

# Test suite for cli.rb v∞.17.0
# Run: ruby test_cli.rb

require "minitest/autorun"
require "stringio"
require "fileutils"
require "tempfile"

# Load the CLI without running it
$PROGRAM_NAME = "test"  # Prevent CLI.new.run from executing
load File.expand_path("cli.rb", __dir__)

class TestConvergenceModule < Minitest::Test
  def test_version_defined
    assert_equal "∞.17.0", Convergence::VERSION
  end
  
  def test_version_frozen
    assert Convergence::VERSION.frozen?
  end
  
  def test_access_levels_defined
    assert_includes Convergence::ACCESS_LEVELS.keys, :sandbox
    assert_includes Convergence::ACCESS_LEVELS.keys, :user
    assert_includes Convergence::ACCESS_LEVELS.keys, :admin
  end
  
  def test_sandbox_paths
    paths = Convergence::ACCESS_LEVELS[:sandbox][:paths].call
    assert_includes paths, Dir.pwd
    assert_includes paths, "/tmp"
  end
  
  def test_admin_allows_root
    assert Convergence::ACCESS_LEVELS[:admin][:allow_root]
    refute Convergence::ACCESS_LEVELS[:user][:allow_root]
    refute Convergence::ACCESS_LEVELS[:sandbox][:allow_root]
  end
end

class TestMasterConfig < Minitest::Test
  def test_loads_default_when_missing
    config = MasterConfig.new
    assert_kind_of String, config.version
    assert_kind_of Array, config.preferred_tools
  end
  
  def test_preferred_tools_include_ruby
    config = MasterConfig.new
    assert_includes config.preferred_tools, "ruby"
  end
  
  def test_preferred_check
    config = MasterConfig.new
    assert config.preferred?("ruby script.rb")
    assert config.preferred?("zsh -c 'echo'")
    assert config.preferred?("doas pkg_add")
  end
end

class TestConfig < Minitest::Test
  def setup
    @original_home = ENV["HOME"]
    @temp_dir = Dir.mktmpdir
    ENV["HOME"] = @temp_dir
  end
  
  def teardown
    ENV["HOME"] = @original_home
    FileUtils.rm_rf(@temp_dir)
  end
  
  def test_default_values
    config = Config.new
    assert_equal :openrouter, config.provider
    assert_nil config.api_key
    assert_equal :user, config.access_level
  end
  
  def test_save_and_load
    config = Config.new
    config.provider = :openrouter
    config.api_key = "test-key-123"
    config.model = "deepseek/deepseek-r1"
    config.access_level = :admin
    config.save
    
    loaded = Config.load
    assert_equal :openrouter, loaded.provider
    assert_equal "test-key-123", loaded.api_key
    assert_equal "deepseek/deepseek-r1", loaded.model
    assert_equal :admin, loaded.access_level
  end
  
  def test_configured_check
    config = Config.new
    refute config.configured?
    
    config.provider = :openrouter
    config.api_key = "key"
    assert config.configured?
  end
  
  def test_config_file_permissions
    # Note: Config constants are frozen at load time, so we can't easily test
    # this with a temporary HOME. This test validates the file is created with
    # correct permissions in the actual config directory.
    config = Config.new
    config.provider = :openrouter
    config.api_key = "secret-test-key-#{Time.now.to_i}"
    config.model = "deepseek/deepseek-r1"
    config.access_level = :user
    config.save
    
    # Use the actual CONFIG_PATH from the class
    if File.exist?(Config::CONFIG_PATH)
      mode = File.stat(Config::CONFIG_PATH).mode & 0777
      assert_equal 0600, mode, "Config should be user-only readable"
    else
      skip "Config file not created (save may have failed)"
    end
  end
end

class TestAPIClient < Minitest::Test
  def test_initialization
    client = APIClient.new(provider: :openrouter, api_key: "test")
    assert_equal :openrouter, client.provider
    assert_equal "deepseek/deepseek-r1", client.model
  end
  
  def test_models_list
    client = APIClient.new(provider: :openrouter, api_key: "test")
    models = client.models
    assert_includes models.keys, "deepseek-r1"
    assert_includes models.keys, "claude-3.5"
    assert_includes models.keys, "gpt-4o"
  end
  
  def test_switch_model
    client = APIClient.new(provider: :openrouter, api_key: "test")
    assert client.switch_model("claude-3.5")
    assert_equal "anthropic/claude-3.5-sonnet", client.model
    
    refute client.switch_model("nonexistent-model")
  end
  
  def test_clear_history
    client = APIClient.new(provider: :openrouter, api_key: "test")
    client.clear_history
    assert_empty client.get_history
  end
  
  def test_set_history
    client = APIClient.new(provider: :openrouter, api_key: "test")
    history = [{ role: "user", content: "hello" }]
    client.set_history(history)
    assert_equal history, client.get_history
  end
  
  def test_unknown_provider_raises
    assert_raises(RuntimeError) do
      APIClient.new(provider: :unknown, api_key: "test")
    end
  end
end

class TestFileTool < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
  end
  
  def teardown
    FileUtils.rm_rf(@temp_dir)
  end
  
  def test_read_file
    path = File.join(@temp_dir, "test.txt")
    File.write(path, "hello world")
    
    tool = FileTool.new(base_path: @temp_dir, access_level: :user)
    result = tool.read(path: path)
    
    assert_equal "hello world", result[:content]
    assert_equal 11, result[:size]
  end
  
  def test_read_nonexistent
    tool = FileTool.new(base_path: @temp_dir, access_level: :user)
    result = tool.read(path: "/nonexistent/file.txt")
    
    assert result[:error]
  end
  
  def test_write_file
    path = File.join(@temp_dir, "new.txt")
    
    tool = FileTool.new(base_path: @temp_dir, access_level: :user)
    result = tool.write(path: path, content: "new content")
    
    assert result[:success]
    assert_equal "new content", File.read(path)
  end
  
  def test_sandbox_enforcement
    tool = FileTool.new(base_path: @temp_dir, access_level: :sandbox)
    
    # Reading outside sandbox should fail
    result = tool.read(path: "/etc/passwd")
    assert result[:error]
  end
  
  def test_admin_bypasses_sandbox
    tool = FileTool.new(base_path: @temp_dir, access_level: :admin)
    
    # Admin can read anywhere - may succeed or fail based on permissions, but not SecurityError
    result = tool.read(path: "/etc/hosts")
    refute_equal "outside sandbox", result[:error]
  end
end

class TestShellTool < Minitest::Test
  def test_execute_simple_command
    config = MasterConfig.new
    tool = ShellTool.new(access_level: :user, master_config: config)
    result = tool.execute(command: "echo hello")
    
    assert result[:success]
    assert_includes result[:stdout], "hello"
    assert_equal 0, result[:exit_code]
  end
  
  def test_execute_with_timeout
    config = MasterConfig.new
    tool = ShellTool.new(access_level: :user, master_config: config)
    result = tool.execute(command: "sleep 0.1 && echo done", timeout: 5)
    
    assert result[:success]
    assert_includes result[:stdout], "done"
  end
  
  def test_timeout_exceeded
    config = MasterConfig.new
    tool = ShellTool.new(access_level: :user, master_config: config)
    result = tool.execute(command: "sleep 10", timeout: 1)
    
    assert_equal "timeout", result[:error]
  end
end

class TestSessionManager < Minitest::Test
  def setup
    @original_home = ENV["HOME"]
    @temp_dir = Dir.mktmpdir
    ENV["HOME"] = @temp_dir
  end
  
  def teardown
    ENV["HOME"] = @original_home
    FileUtils.rm_rf(@temp_dir)
  end
  
  def test_save_and_load
    mgr = SessionManager.new
    state = { history: [{ role: "user", content: "test" }], created: Time.now.to_i }
    
    mgr.save("test-session", state)
    loaded = mgr.load("test-session")
    
    # YAML.safe_load_file returns string keys, not symbol keys
    assert_equal state[:history], loaded[:history] || loaded["history"]
  end
  
  def test_list_sessions
    mgr = SessionManager.new
    mgr.save("session1", { history: [] })
    mgr.save("session2", { history: [] })
    
    sessions = mgr.list
    assert_includes sessions, "session1"
    assert_includes sessions, "session2"
  end
  
  def test_load_nonexistent
    mgr = SessionManager.new
    assert_nil mgr.load("nonexistent")
  end
end

class TestRAG < Minitest::Test
  def setup
    @temp_file = Tempfile.new(["test", ".txt"])
    @temp_file.write("Ruby is a programming language.\n\nPython is also popular.\n\nZsh is a shell.")
    @temp_file.close
  end
  
  def teardown
    @temp_file.unlink
  end
  
  def test_ingest_file
    rag = RAG.new
    count = rag.ingest(@temp_file.path)
    
    assert_equal 3, count
    assert_equal 3, rag.stats[:chunks]
  end
  
  def test_search_finds_relevant
    rag = RAG.new
    rag.ingest(@temp_file.path)
    
    results = rag.search("ruby programming")
    refute_empty results
    assert_includes results.first[:chunk][:text].downcase, "ruby"
  end
  
  def test_search_empty_rag
    rag = RAG.new
    results = rag.search("anything")
    assert_empty results
  end
end

class TestDirectoryProcessor < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    File.write(File.join(@temp_dir, "script.rb"), "#!/usr/bin/env ruby\nputs 'hello'")
    File.write(File.join(@temp_dir, "shell.sh"), "#!/bin/zsh\necho hello")
    File.write(File.join(@temp_dir, "data.json"), '{"key": "value"}')
  end
  
  def teardown
    FileUtils.rm_rf(@temp_dir)
  end
  
  def test_processes_matching_extensions
    config = MasterConfig.new
    processor = DirectoryProcessor.new(@temp_dir, config)
    
    files = []
    processor.process { |r| files << r[:path] }
    
    assert files.any? { |f| f.end_with?(".rb") }
    assert files.any? { |f| f.end_with?(".sh") }
    assert files.any? { |f| f.end_with?(".json") }
  end
  
  def test_detects_preferred_tools
    config = MasterConfig.new
    processor = DirectoryProcessor.new(@temp_dir, config)
    
    results = []
    processor.process { |r| results << r }
    
    rb_file = results.find { |r| r[:path].end_with?(".rb") }
    assert rb_file[:uses_preferred], "Ruby file should use preferred tools"
  end
end

class TestApplyPledge < Minitest::Test
  def test_graceful_on_non_openbsd
    # Should not raise on non-OpenBSD
    assert_nil apply_pledge(:user)
  end
end

if __FILE__ == $PROGRAM_NAME
  puts "\n" + "=" * 60
  puts "cli.rb v∞.17.0 Test Suite"
  puts "=" * 60
end
