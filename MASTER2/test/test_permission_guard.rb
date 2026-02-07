# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestPermissionGuard < Minitest::Test
  def setup
    @executor = MASTER::Executor.new
  end

  def test_constitution_file_exists
    assert File.exist?(MASTER::Executor::CONSTITUTION_FILE)
  end

  def test_constitution_loads
    const = MASTER::Executor.constitution
    assert const.is_a?(Hash)
    assert const.key?("tool_permissions")
  end

  def test_constitution_has_immutable_flag
    const = MASTER::Executor.constitution
    assert_equal true, const["immutable"]
  end

  # Shell command permission tests
  def test_shell_command_blocks_dangerous_rm
    result = @executor.send(:check_shell_permission, "rm -rf /")
    assert result.is_a?(String)
    assert_includes result, "BLOCKED"
  end

  def test_shell_command_blocks_dev_write
    result = @executor.send(:check_shell_permission, "echo test > /dev/sda")
    assert result.is_a?(String)
    assert_includes result, "BLOCKED"
  end

  def test_shell_command_blocks_drop_table
    result = @executor.send(:check_shell_permission, "DROP TABLE users")
    assert result.is_a?(String)
    assert_includes result, "BLOCKED"
  end

  def test_shell_command_allows_ls
    result = @executor.send(:check_shell_permission, "ls -la")
    assert_equal true, result
  end

  def test_shell_command_allows_pwd
    result = @executor.send(:check_shell_permission, "pwd")
    assert_equal true, result
  end

  def test_shell_command_allows_git_status
    result = @executor.send(:check_shell_permission, "git status")
    assert_equal true, result
  end

  def test_shell_command_allows_echo
    result = @executor.send(:check_shell_permission, "echo hello")
    assert_equal true, result
  end

  def test_shell_command_allows_ruby
    result = @executor.send(:check_shell_permission, "ruby -v")
    assert_equal true, result
  end

  # Code execution permission tests
  def test_code_execution_blocks_system
    code = 'system("rm -rf /")'
    result = @executor.send(:check_code_execution_permission, code)
    assert result.is_a?(String)
    assert_includes result, "BLOCKED"
  end

  def test_code_execution_blocks_exec
    code = 'exec("malicious command")'
    result = @executor.send(:check_code_execution_permission, code)
    assert result.is_a?(String)
    assert_includes result, "BLOCKED"
  end

  def test_code_execution_blocks_backticks
    code = '`rm important_file`'
    result = @executor.send(:check_code_execution_permission, code)
    assert result.is_a?(String)
    assert_includes result, "BLOCKED"
  end

  def test_code_execution_allows_safe_code
    code = 'puts "Hello World"'
    result = @executor.send(:check_code_execution_permission, code)
    assert_equal true, result
  end

  def test_code_execution_allows_math
    code = "x = 2 + 2\nputs x"
    result = @executor.send(:check_code_execution_permission, code)
    assert_equal true, result
  end

  # File write permission tests
  def test_file_write_blocks_constitution
    result = @executor.send(:check_file_write_permission, "data/constitution.yml")
    assert result.is_a?(String)
    assert_includes result, "BLOCKED"
    assert_includes result, "constitution.yml"
  end

  def test_file_write_blocks_etc
    result = @executor.send(:check_file_write_permission, "/etc/passwd")
    assert result.is_a?(String)
    assert_includes result, "BLOCKED"
  end

  def test_file_write_blocks_usr
    result = @executor.send(:check_file_write_permission, "/usr/local/bin/malware")
    assert result.is_a?(String)
    assert_includes result, "BLOCKED"
  end

  def test_file_write_allows_normal_path
    result = @executor.send(:check_file_write_permission, "lib/test.rb")
    assert_equal true, result
  end

  def test_file_write_allows_tmp
    result = @executor.send(:check_file_write_permission, "/tmp/test.txt")
    assert_equal true, result
  end

  # Integration: actual tool execution
  def test_shell_command_enforces_permissions
    result = @executor.send(:shell_command, "rm -rf /")
    assert_includes result, "BLOCKED"
  end

  def test_shell_command_allows_safe_commands
    result = @executor.send(:shell_command, "echo test")
    assert_includes result.downcase, "test"
  end

  def test_file_write_enforces_constitution_protection
    result = @executor.send(:file_write, "data/constitution.yml", "malicious content")
    assert_includes result, "BLOCKED"
    assert_includes result, "constitution.yml"
  end

  def test_code_execution_enforces_permissions
    result = @executor.send(:code_execution, 'system("rm -rf /")')
    assert_includes result, "BLOCKED"
  end
end
