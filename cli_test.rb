#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require_relative "cli"

class TestMasterConfig < Minitest::Test
  def setup
    @master = MasterConfig.new
  end
  
  def test_version_loaded
    refute_nil @master.version
  end
  
  def test_preferred_tools_present
    assert_kind_of Array, @master.preferred_tools
    refute_empty @master.preferred_tools
  end
  
  def test_preferred_detection
    assert @master.preferred?("ruby script.rb")
    assert @master.preferred?("zsh -c 'echo test'")
    assert @master.preferred?("doas pkg_add vim")
  end
end

class TestConfig < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @original_home = ENV["HOME"]
    ENV["HOME"] = @tmpdir
    @config = Config.new
  end
  
  def teardown
    ENV["HOME"] = @original_home
    FileUtils.rm_rf(@tmpdir)
  end
  
  def test_default_values
    assert_equal :openrouter, @config.provider
    assert_nil @config.api_key
    assert_nil @config.model
    assert_equal :user, @config.access_level
  end
  
  def test_not_configured_without_key
    refute @config.configured?
  end
  
  def test_configured_with_key
    @config.api_key = "test_key"
    @config.provider = :openrouter
    assert @config.configured?
  end
  
  def test_save_and_load
    @config.api_key = "test_key_123"
    @config.provider = :openrouter
    @config.model = "deepseek/deepseek-r1"
    @config.access_level = :sandbox
    @config.save
    
    loaded = Config.load
    assert_equal "test_key_123", loaded.api_key
    assert_equal :openrouter, loaded.provider
    assert_equal "deepseek/deepseek-r1", loaded.model
    assert_equal :sandbox, loaded.access_level
  end
  
  def test_config_file_permissions
    @config.api_key = "test"
    @config.save
    mode = File.stat(Config::CONFIG_PATH).mode & 0777
    assert_equal 0600, mode
  end
end

class TestAPIClient < Minitest::Test
  def setup
    @client = APIClient.new(provider: :openrouter, api_key: "test_key")
  end
  
  def test_initialization
    assert_equal :openrouter, @client.provider
    assert_equal "deepseek/deepseek-r1", @client.model
  end
  
  def test_has_14_models
    models = @client.models
    assert_equal 14, models.size
  end
  
  def test_model_switching
    assert @client.switch_model("claude-3.5")
    assert_equal "anthropic/claude-3.5-sonnet", @client.model
  end
  
  def test_model_switching_with_full_name
    assert @client.switch_model("openai/gpt-4o")
    assert_equal "openai/gpt-4o", @client.model
  end
  
  def test_invalid_model
    refute @client.switch_model("nonexistent-model")
  end
  
  def test_history_management
    assert_empty @client.get_history
    
    @client.instance_variable_set(:@messages, [{ role: "user", content: "test" }])
    refute_empty @client.get_history
    
    @client.clear_history
    assert_empty @client.get_history
  end
  
  def test_set_history
    msgs = [{ role: "user", content: "hello" }]
    @client.set_history(msgs)
    assert_equal msgs, @client.get_history
  end
end

class TestAccessLevels < Minitest::Test
  def test_all_levels_defined
    assert Convergence::ACCESS_LEVELS.key?(:sandbox)
    assert Convergence::ACCESS_LEVELS.key?(:user)
    assert Convergence::ACCESS_LEVELS.key?(:admin)
  end
  
  def test_sandbox_restrictions
    sandbox = Convergence::ACCESS_LEVELS[:sandbox]
    refute sandbox[:allow_root]
    assert sandbox[:confirm_writes]
    assert sandbox[:confirm_deletes]
  end
  
  def test_user_restrictions
    user = Convergence::ACCESS_LEVELS[:user]
    refute user[:allow_root]
    refute user[:confirm_writes]
    assert user[:confirm_deletes]
  end
  
  def test_admin_permissions
    admin = Convergence::ACCESS_LEVELS[:admin]
    assert admin[:allow_root]
    assert admin[:confirm_writes]
    assert admin[:confirm_deletes]
    assert admin[:confirm_root]
  end
  
  def test_sandbox_paths
    paths = Convergence::ACCESS_LEVELS[:sandbox][:paths].call
    assert_includes paths, Dir.pwd
    assert_includes paths, "/tmp"
    assert_equal 2, paths.size
  end
  
  def test_admin_all_paths
    paths = Convergence::ACCESS_LEVELS[:admin][:paths].call
    assert_equal :all, paths
  end
end

class TestDirectoryProcessor < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @master = MasterConfig.new
  end
  
  def teardown
    FileUtils.rm_rf(@tmpdir)
  end
  
  def test_processes_ruby_files
    File.write(File.join(@tmpdir, "test.rb"), "puts 'hello'")
    processor = DirectoryProcessor.new(@tmpdir, @master)
    results = []
    processor.process { |r| results << r }
    assert_equal 1, results.size
    assert_equal 1, results.first[:lines]
  end
  
  def test_detects_preferred_tools
    File.write(File.join(@tmpdir, "script.rb"), "system('ruby test.rb')")
    processor = DirectoryProcessor.new(@tmpdir, @master)
    results = []
    processor.process { |r| results << r }
    assert results.first[:uses_preferred]
  end
  
  def test_ignores_unsupported_extensions
    File.write(File.join(@tmpdir, "test.bin"), "binary")
    processor = DirectoryProcessor.new(@tmpdir, @master)
    results = []
    processor.process { |r| results << r }
    assert_empty results
  end
end

class TestFileTool < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @tool = FileTool.new(base_path: @tmpdir, access_level: :sandbox)
  end
  
  def teardown
    FileUtils.rm_rf(@tmpdir)
  end
  
  def test_read_file
    path = File.join(@tmpdir, "test.txt")
    File.write(path, "content")
    result = @tool.read(path: path)
    assert_equal "content", result[:content]
    assert_equal 7, result[:size]
  end
  
  def test_read_nonexistent_file
    result = @tool.read(path: File.join(@tmpdir, "missing.txt"))
    assert result[:error]
  end
  
  def test_write_file
    path = File.join(@tmpdir, "new.txt")
    result = @tool.write(path: path, content: "test")
    assert result[:success]
    assert File.exist?(path)
    assert_equal "test", File.read(path)
  end
  
  def test_sandbox_enforcement
    outside = "/etc/passwd"
    result = @tool.read(path: outside)
    assert result[:error]
    assert_match(/sandbox/, result[:error])
  end
end

class TestShellTool < Minitest::Test
  def setup
    @master = MasterConfig.new
    @tool = ShellTool.new(access_level: :user, master_config: @master)
  end
  
  def test_execute_simple_command
    result = @tool.execute(command: "echo test")
    assert result[:success]
    assert_match(/test/, result[:stdout])
  end
  
  def test_command_timeout
    result = @tool.execute(command: "sleep 2", timeout: 1)
    assert result[:error]
    assert_match(/timeout/, result[:error])
  end
  
  def test_needs_confirmation_for_destructive
    tool = ShellTool.new(access_level: :sandbox, master_config: @master)
    result = tool.execute(command: "rm test.txt")
    assert result[:error]
    assert_match(/confirmation/, result[:error])
  end
end

class TestSessionManager < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @original_home = ENV["HOME"]
    ENV["HOME"] = @tmpdir
    @mgr = SessionManager.new
  end
  
  def teardown
    ENV["HOME"] = @original_home
    FileUtils.rm_rf(@tmpdir)
  end
  
  def test_save_and_load
    state = { history: [{ role: "user", content: "test" }], created: Time.now.to_i }
    @mgr.save("test_session", state)
    
    loaded = @mgr.load("test_session")
    assert_equal state[:history], loaded[:history]
  end
  
  def test_list_sessions
    @mgr.save("session1", {})
    @mgr.save("session2", {})
    
    sessions = @mgr.list
    assert_includes sessions, "session1"
    assert_includes sessions, "session2"
  end
  
  def test_load_nonexistent
    result = @mgr.load("nonexistent")
    assert_nil result
  end
end

class TestRAG < Minitest::Test
  def setup
    @rag = RAG.new
    @tmpdir = Dir.mktmpdir
  end
  
  def teardown
    FileUtils.rm_rf(@tmpdir)
  end
  
  def test_initialization
    assert_equal 0, @rag.stats[:chunks]
  end
  
  def test_ingest_file
    path = File.join(@tmpdir, "test.txt")
    File.write(path, "First paragraph.\n\nSecond paragraph.\n\nThird paragraph.")
    
    count = @rag.ingest(path)
    assert_equal 3, count
    assert_equal 3, @rag.stats[:chunks]
  end
  
  def test_search_simple
    path = File.join(@tmpdir, "test.txt")
    File.write(path, "Ruby is great.\n\nPython is ok.\n\nRuby rocks!")
    @rag.ingest(path)
    
    results = @rag.search("ruby", k: 2)
    assert_equal 2, results.size
    assert results.first[:score] > 0
  end
  
  def test_search_empty_rag
    results = @rag.search("test")
    assert_empty results
  end
  
  def test_ingest_nonexistent_file
    count = @rag.ingest("/nonexistent/file.txt")
    assert_equal 0, count
  end
end

class TestApplyPledge < Minitest::Test
  def test_apply_pledge_without_crash
    # Should not crash even if pledge is not available
    assert_silent { apply_pledge(:user) }
  end
end

class TestConvergenceModule < Minitest::Test
  def test_version_constant
    assert_equal "∞.17.0", Convergence::VERSION
  end
  
  def test_access_levels_frozen
    assert Convergence::ACCESS_LEVELS.frozen?
  end
end
