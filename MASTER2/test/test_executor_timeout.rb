# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestExecutorTimeout < Minitest::Test
  def test_wall_clock_limit_constant
    assert_equal 120, MASTER::Executor::WALL_CLOCK_LIMIT_SECONDS
  end

  def test_max_steps_constant
    assert_equal 15, MASTER::Executor::MAX_STEPS
  end

  def test_dangerous_patterns_references_guard
    # Verify DANGEROUS_PATTERNS is defined in Stages::Guard
    assert MASTER::Stages::Guard::DANGEROUS_PATTERNS.is_a?(Array)
  end

  def test_dangerous_patterns_not_empty
    patterns = MASTER::Stages::Guard::DANGEROUS_PATTERNS
    refute_empty patterns
    assert_kind_of Array, patterns
    patterns.each do |p|
      assert_kind_of Regexp, p
    end
  end

  def test_dangerous_patterns_detects_rm_rf
    patterns = MASTER::Stages::Guard::DANGEROUS_PATTERNS
    dangerous_cmd = "rm -rf /"
    assert patterns.any? { |p| p.match?(dangerous_cmd) }
  end

  def test_dangerous_patterns_detects_drop_table
    patterns = MASTER::Stages::Guard::DANGEROUS_PATTERNS
    dangerous_cmd = "DROP TABLE users"
    assert patterns.any? { |p| p.match?(dangerous_cmd) }
  end

  def test_dangerous_patterns_detects_disk_operations
    patterns = MASTER::Stages::Guard::DANGEROUS_PATTERNS
    assert patterns.any? { |p| p.match?("dd if=/dev/zero") }
    assert patterns.any? { |p| p.match?("mkfs.ext4") }
  end

  def test_executor_initializes_with_custom_max_steps
    executor = MASTER::Executor.new(max_steps: 5)
    assert_equal 5, executor.max_steps
  end
end
