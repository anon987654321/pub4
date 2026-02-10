require_relative "test_helper"

class TestSafety < Minitest::Test
  def test_dangerous_patterns_detection
    assert MASTER::Safety.dangerous?("rm -rf /")
    assert MASTER::Safety.dangerous?("DROP TABLE users")
    assert MASTER::Safety.dangerous?("FORMAT C:")
    assert MASTER::Safety.dangerous?("mkfs.ext4 /dev/sda")
    assert MASTER::Safety.dangerous?("dd if=/dev/zero")
    refute MASTER::Safety.dangerous?("echo hello")
    refute MASTER::Safety.dangerous?("git status")
  end

  def test_protected_paths
    assert MASTER::Safety.protected_path?("/etc/passwd")
    assert MASTER::Safety.protected_path?("/usr/bin/ruby")
    assert MASTER::Safety.protected_path?("/sys/kernel")
    assert MASTER::Safety.protected_path?("/proc/cpuinfo")
    assert MASTER::Safety.protected_path?("/dev/sda")
    assert MASTER::Safety.protected_path?("/boot/grub")
    refute MASTER::Safety.protected_path?("/home/user/file.txt")
    refute MASTER::Safety.protected_path?("/tmp/test.rb")
  end

  def test_dangerous_pattern_case_insensitive
    assert MASTER::Safety.dangerous?("drop table users")
    assert MASTER::Safety.dangerous?("Drop Table users")
    assert MASTER::Safety.dangerous?("format c:")
  end
end
