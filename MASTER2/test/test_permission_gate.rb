# frozen_string_literal: true

require_relative "test_helper"

class TestPermissionGate < Minitest::Test
  def setup
    @executor = MASTER::Executor.new
  end

  # Test protected write paths constant exists
  def test_protected_write_paths_constant
    assert_includes MASTER::Executor::PROTECTED_WRITE_PATHS.to_s, "constitution"
  end

  # Test constitution file write is blocked
  def test_blocks_write_to_constitution
    result = @executor.send(:file_write, "data/constitution.yml", "malicious content")
    assert_includes result, "BLOCKED"
    assert_includes result, "constitution"
  end

  # Test constitution file write is blocked with absolute path
  def test_blocks_write_to_constitution_absolute_path
    path = File.expand_path("MASTER2/data/constitution.yml")
    result = @executor.send(:file_write, path, "malicious content")
    assert_includes result, "BLOCKED"
    assert_includes result, "constitution"
  end

  # Test system paths are blocked
  def test_blocks_write_to_etc
    result = @executor.send(:file_write, "/etc/passwd", "malicious content")
    assert_includes result, "BLOCKED"
  end

  def test_blocks_write_to_sys
    result = @executor.send(:file_write, "/sys/kernel", "malicious content")
    assert_includes result, "BLOCKED"
  end

  def test_blocks_write_to_proc
    result = @executor.send(:file_write, "/proc/sys", "malicious content")
    assert_includes result, "BLOCKED"
  end

  def test_blocks_write_to_dev
    result = @executor.send(:file_write, "/dev/null", "malicious content")
    assert_includes result, "BLOCKED"
  end

  # Test that normal file writes still work
  def test_allows_write_to_temp_file
    # Create temp file within working directory
    Dir.mktmpdir do |dir|
      path = File.join(Dir.pwd, "test_file.txt")
      
      result = @executor.send(:file_write, path, "safe content")
      assert_includes result, "Written"
      assert_equal "safe content", File.read(path) if File.exist?(path)
      
      # Cleanup
      File.delete(path) if File.exist?(path)
    end
  end

  # Test dangerous shell patterns are still blocked
  def test_blocks_dangerous_shell_rm_rf
    result = @executor.send(:shell_command, "rm -rf /")
    assert_includes result, "BLOCKED"
  end

  def test_blocks_dangerous_shell_drop_table
    result = @executor.send(:shell_command, "psql -c 'DROP TABLE users'")
    assert_includes result, "BLOCKED"
  end

  # Test safe shell commands still work
  def test_allows_safe_shell_echo
    result = @executor.send(:shell_command, "echo hello")
    assert_includes result.downcase, "hello"
  end
end
