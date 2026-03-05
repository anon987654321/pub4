# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestPermissionGate < Minitest::Test
  def setup
    @executor = MASTER::Executor.new
  end

  def test_protected_write_paths_constant
    assert defined?(MASTER::Executor::PROTECTED_WRITE_PATHS)
    assert MASTER::Executor::PROTECTED_WRITE_PATHS.include?("data/constitution.yml")
  end

  def test_file_write_blocks_constitution
    result = @executor.send(:file_write, "data/constitution.yml", "malicious content")
    assert_match(/BLOCKED/, result)
    assert_match(/protected path/, result)
  end

  def test_file_write_blocks_system_paths
    result = @executor.send(:file_write, "/etc/passwd", "malicious")
    assert_match(/BLOCKED/, result)
  end

  def test_file_write_allows_normal_paths
    # Create a temp file in current directory
    test_file = "tmp_test_file.txt"
    result = @executor.send(:file_write, test_file, "test content")
    
    assert_match(/Written/, result)
    
    # Cleanup
    File.delete(test_file) if File.exist?(test_file)
  end

  def test_shell_command_blocks_dangerous_patterns
    result = @executor.send(:shell_command, "rm -rf /")
    assert_match(/BLOCKED/, result)
  end

  def test_shell_command_allows_safe_commands
    result = @executor.send(:shell_command, "echo hello")
    assert_match(/hello/, result)
  end

  def test_code_execution_blocks_system_calls
    result = @executor.send(:code_execution, "system('rm -rf /')")
    assert_match(/BLOCKED/, result)
    assert_match(/dangerous constructs/, result)
  end

  def test_code_execution_blocks_exec
    result = @executor.send(:code_execution, "exec('malicious')")
    assert_match(/BLOCKED/, result)
  end

  def test_code_execution_blocks_backticks
    result = @executor.send(:code_execution, "`rm -rf /`")
    assert_match(/BLOCKED/, result)
  end

  def test_code_execution_allows_safe_ruby
    result = @executor.send(:code_execution, "puts 2 + 2")
    refute_match(/BLOCKED/, result)
  end

  def test_check_tool_permission_method_exists
    result = @executor.send(:check_tool_permission, :shell_command)
    assert result.ok?
  end
end
