# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestPermissionGate < Minitest::Test
  def setup
    MASTER::DB.setup(path: ":memory:")
  end

  def test_unrestricted_tools_allowed_by_default
    # Tools like ask_llm should be unrestricted
    result = MASTER::Executor.tool_permitted?(:ask_llm, {})
    assert result, "ask_llm should be allowed without explicit permission"
  end
  
  def test_restricted_tools_blocked_without_permission
    # Dangerous tools should require explicit permission
    result = MASTER::Executor.tool_permitted?(:shell_command, {})
    refute result, "shell_command should be blocked without explicit permission"
  end
  
  def test_restricted_tools_allowed_with_permission
    result = MASTER::Executor.tool_permitted?(:shell_command, { explicit_permission: true })
    assert result, "shell_command should be allowed with explicit permission"
  end
  
  def test_code_execution_blocked_without_permission
    result = MASTER::Executor.tool_permitted?(:code_execution, {})
    refute result, "code_execution should be blocked without explicit permission"
  end
  
  def test_code_execution_allowed_with_permission
    result = MASTER::Executor.tool_permitted?(:code_execution, { explicit_permission: true })
    assert result, "code_execution should be allowed with explicit permission"
  end
  
  def test_file_write_blocked_without_permission
    result = MASTER::Executor.tool_permitted?(:file_write, {})
    refute result, "file_write should be blocked without explicit permission"
  end
  
  def test_file_write_allowed_with_permission
    result = MASTER::Executor.tool_permitted?(:file_write, { explicit_permission: true })
    assert result, "file_write should be allowed with explicit permission"
  end
  
  def test_executor_blocks_shell_without_permission
    executor = MASTER::Executor.new
    result = executor.send(:execute_tool, "shell_command 'ls'")
    assert result.start_with?("BLOCKED:")
    assert_match(/explicit permission/, result)
  end
  
  def test_executor_blocks_code_execution_without_permission
    executor = MASTER::Executor.new
    result = executor.send(:execute_tool, "code_execution ```ruby\nputs 'hello'\n```")
    assert result.start_with?("BLOCKED:")
  end
  
  def test_executor_allows_shell_with_permission
    executor = MASTER::Executor.new(permissions: { explicit_permission: true })
    result = executor.send(:execute_tool, "shell_command 'echo test'")
    refute result.start_with?("BLOCKED:")
  end
  
  def test_executor_blocks_constitution_write
    executor = MASTER::Executor.new(permissions: { explicit_permission: true })
    result = executor.send(:execute_tool, 
      "file_write 'data/constitution.yml' 'malicious: true'")
    assert result.start_with?("BLOCKED:")
    assert_match(/constitution/, result)
  end
end
