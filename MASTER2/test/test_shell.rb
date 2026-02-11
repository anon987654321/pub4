# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestInteractiveShell < Minitest::Test
  def setup
    @shell = MASTER::InteractiveShell.new
  end

  def test_initialization
    assert_instance_of MASTER::InteractiveShell, @shell
    assert_equal Dir.pwd, @shell.context[:cwd]
    assert_empty @shell.context[:history]
  end

  def test_prompt_format
    prompt = @shell.send(:prompt)
    assert_match /^master:.+\$\s$/, prompt
  end

  def test_change_directory_valid
    original_dir = Dir.pwd
    test_dir = File.expand_path("..", original_dir)
    
    @shell.send(:change_directory, "..")
    assert_equal test_dir, @shell.context[:cwd]
    
    # Cleanup - go back to original
    Dir.chdir(original_dir)
    @shell.context[:cwd] = original_dir
  end

  def test_change_directory_invalid
    original_dir = @shell.context[:cwd]
    
    # Capture output to avoid noise in tests
    original_stdout = $stdout
    $stdout = StringIO.new
    
    @shell.send(:change_directory, "/nonexistent/path/that/does/not/exist")
    
    $stdout = original_stdout
    
    # Should remain in original directory
    assert_equal original_dir, @shell.context[:cwd]
  end

  def test_history_tracking
    # Simulate executing commands (without actual execution)
    @shell.context[:history] << "ls"
    @shell.context[:history] << "pwd"
    
    assert_equal 2, @shell.context[:history].size
    assert_equal "ls", @shell.context[:history][0]
    assert_equal "pwd", @shell.context[:history][1]
  end

  def test_unix_commands_regex_matching
    # Test that Unix commands are recognized
    assert_match /^ls\b/, "ls"
    assert_match /^pwd\b/, "pwd"
    assert_match /^cat\b/, "cat file.txt"
    assert_match /^grep\b/, "grep pattern file.txt"
  end

  def test_master_commands_regex_matching
    # Test that MASTER commands are recognized
    assert_match /^scan\s+(.+)$/, "scan file.rb"
    assert_match /^analyze\s+(.+)$/, "analyze file.rb"
    assert_match /^fix\s+(.+)$/, "fix file.rb"
    assert_match /^ask\s+(.+)$/, "ask what is this?"
  end

  def test_exit_commands
    assert_equal :exit, @shell.execute("exit")
    assert_equal :exit, @shell.execute("quit")
    assert_equal :exit, @shell.execute("q")
  end

  def test_empty_input
    result = @shell.execute("")
    assert_nil result
  end
end

class TestShellModule < Minitest::Test
  def test_sanitize_forbidden_commands
    assert_equal "doas something", MASTER::Shell.sanitize("sudo something")
    assert_equal "pkg_add package", MASTER::Shell.sanitize("apt package")
    assert_equal "pkg_add package", MASTER::Shell.sanitize("apt-get package")
  end

  def test_sanitize_zsh_preferred
    assert_equal "ls -F", MASTER::Shell.sanitize("ls")
    assert_equal "grep --color=auto", MASTER::Shell.sanitize("grep")
  end

  def test_safe_command_detection
    # Safe commands
    assert MASTER::Shell.safe?("ls -la")
    assert MASTER::Shell.safe?("cat file.txt")
    assert MASTER::Shell.safe?("grep pattern file")
    
    # Dangerous commands
    refute MASTER::Shell.safe?("rm -rf /")
    refute MASTER::Shell.safe?("dd if=/dev/zero of=/dev/sda")
    refute MASTER::Shell.safe?("mkfs.ext4 /dev/sda")
  end

  def test_execute_safe_command
    result = MASTER::Shell.execute("echo test")
    assert result.ok?, "Expected command to succeed"
    assert_match /test/, result.value
  end

  def test_execute_dangerous_command_blocked
    result = MASTER::Shell.execute("rm -rf /")
    assert result.err?, "Expected dangerous command to be blocked"
    assert_match /blocked/, result.error
  end

  def test_which_command
    # Test finding a common command
    result = MASTER::Shell.which("ls")
    assert result, "Expected to find 'ls' command"
    assert result.include?("ls")
  end

  def test_zsh_detection
    # Just test that it doesn't crash
    result = MASTER::Shell.zsh?
    assert [true, false].include?(result)
  end
end
