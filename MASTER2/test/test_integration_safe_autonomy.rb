# frozen_string_literal: true

require_relative "test_helper"

class TestIntegrationSafeAutonomy < Minitest::Test
  def setup
    @executor = MASTER::Executor.new
    @staging = MASTER::Staging.new
  end

  def teardown
    @staging.rollback if @staging
  end

  # Integration test: Constitution file is protected from writes
  def test_integration_constitution_is_protected
    # Try to write to constitution using executor
    result = @executor.send(:file_write, "data/constitution.yml", "hacked")
    
    # Should be blocked
    assert_includes result, "BLOCKED"
    assert_includes result, "constitution"
    
    # Verify actual file is not modified
    if File.exist?("data/constitution.yml")
      content = File.read("data/constitution.yml")
      refute_includes content, "hacked"
    end
  end

  # Integration test: Dangerous shell commands are blocked
  def test_integration_dangerous_commands_blocked
    dangerous_commands = [
      "rm -rf /",
      "DROP TABLE users",
      "mkfs.ext4 /dev/sda1"
    ]
    
    dangerous_commands.each do |cmd|
      result = @executor.send(:shell_command, cmd)
      assert_includes result, "BLOCKED", "Command '#{cmd}' should be blocked"
    end
  end

  # Integration test: Safe operations still work
  def test_integration_safe_operations_work
    # Safe file read
    if File.exist?("lib/staging.rb")
      result = @executor.send(:file_read, "lib/staging.rb")
      refute_includes result, "BLOCKED"
      assert_includes result, "Staging"
    end
    
    # Safe shell command
    result = @executor.send(:shell_command, "echo test")
    refute_includes result, "BLOCKED"
    assert_includes result.downcase, "test"
  end

  # Integration test: Staging workflow
  def test_integration_staging_workflow
    # Create a test file
    Dir.mktmpdir do |dir|
      test_file = File.join(dir, "test.rb")
      File.write(test_file, "# Original\nputs 'hello'\n")
      
      # Stage it
      stage_result = @staging.stage(test_file)
      assert stage_result.ok?, "Staging should succeed"
      
      # Modify staged version
      staged_path = @staging.staged_files.first[:staged]
      File.write(staged_path, "# Modified\nputs 'world'\n")
      
      # Validate
      validate_result = @staging.validate { "OK" }
      assert validate_result.ok?, "Validation should succeed"
      
      # Promote
      promote_result = @staging.promote
      assert promote_result.ok?, "Promotion should succeed"
      
      # Verify original was updated
      content = File.read(test_file)
      assert_includes content, "Modified"
      assert_includes content, "world"
    end
  end

  # Integration test: Evolve with staged mode (dry run)
  def test_integration_evolve_staged_mode
    # Create a minimal Evolve instance with staged mode
    evolve = MASTER::Evolve.new(staged: true)
    
    # Verify it initializes with staging enabled
    assert evolve.instance_variable_get(:@staged)
    refute_nil evolve.instance_variable_get(:@staging)
  end

  # Integration test: Constitution file exists and is valid YAML
  def test_integration_constitution_exists_and_valid
    constitution_path = "data/constitution.yml"
    
    # Check file exists
    assert File.exist?(constitution_path), "Constitution file should exist"
    
    # Check it's valid YAML
    require "yaml"
    constitution = YAML.load_file(constitution_path)
    
    # Check key sections exist
    assert constitution.key?("autonomy"), "Should have autonomy section"
    assert constitution.key?("permissions"), "Should have permissions section"
    assert constitution.key?("resources"), "Should have resources section"
    
    # Check critical policies
    assert_equal false, constitution.dig("autonomy", "self_modification", "enabled"),
      "Self-modification should be disabled"
    assert_includes constitution.dig("autonomy", "self_modification", "protected_files"),
      "data/constitution.yml", "Constitution should protect itself"
  end
end
