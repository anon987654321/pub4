# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestConstitution < Minitest::Test
  def test_rules_loading_with_file
    skip "Constitution schema changed"
    rules = MASTER::Constitution.rules
    
    assert rules.is_a?(Hash)
    assert rules.key?("safety_policies")
    assert rules.key?("tool_permissions")
    assert rules.key?("shell_patterns")
    assert rules.key?("protected_paths")
    assert rules.key?("resource_limits")
  end

  def test_rules_defaults_when_file_missing

    skip "Constitution schema changed"
    # Rules should load with defaults even if file is missing
    rules = MASTER::Constitution.rules
    
    assert rules["safety_policies"]["self_modification"]["require_staging"]
    assert_equal false, rules["safety_policies"]["environment_control"]["direct_control"]
  end

  def test_check_operation_self_modification
    # Without staging should fail
    result = MASTER::Constitution.check_operation(:self_modification, staged: false)
    refute result.ok?
    assert_match(/staging/, result.error)
    
    # With staging should pass
    result = MASTER::Constitution.check_operation(:self_modification, staged: true)
    assert result.ok?
  end

  def test_check_operation_environment_control
    result = MASTER::Constitution.check_operation(:environment_control)
    refute result.ok?
    assert_match(/environment control/, result.error)
  end

  def test_permission_granted_tools
    assert MASTER::Constitution.permission?(:shell_command)
    assert MASTER::Constitution.permission?(:code_execution)
    assert MASTER::Constitution.permission?(:file_write)
  end

  def test_permission_denied_tools
    refute MASTER::Constitution.permission?(:fake_tool)
  end

  def test_protected_file_detection
    assert MASTER::Constitution.protected_file?("data/constitution.yml")
    assert MASTER::Constitution.protected_file?("/etc/passwd")
    assert MASTER::Constitution.protected_file?("/usr/bin/something")
    refute MASTER::Constitution.protected_file?("lib/some_file.rb")
  end

  def test_limit_values
    assert_equal 1048576, MASTER::Constitution.limit(:max_file_size)
    assert_equal 5, MASTER::Constitution.limit(:max_concurrent_tools)
    assert_equal 10, MASTER::Constitution.limit(:max_staging_files)
  end

  def test_check_operation_shell_command_blocked
    result = MASTER::Constitution.check_operation(:shell_command, command: "rm -rf /")
    refute result.ok?
    assert_match(/blocked/, result.error)
  end

  def test_check_operation_shell_command_allowed
    result = MASTER::Constitution.check_operation(:shell_command, command: "ls -la")
    assert result.ok?
  end

  def test_check_operation_file_write_protected
    result = MASTER::Constitution.check_operation(:file_write, path: "data/constitution.yml")
    refute result.ok?
    assert_match(/protected/, result.error)
  end

  def test_check_operation_file_write_allowed
    result = MASTER::Constitution.check_operation(:file_write, path: "tmp/test.txt")
    assert result.ok?
  end
end
