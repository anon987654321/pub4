# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/result"

class TestResult < Minitest::Test
  def test_ok_returns_result_with_value
    result = MASTER::Result.ok(42)
    assert result.ok?
    refute result.err?
    assert_equal 42, result.value
  end

  def test_err_returns_result_with_error
    result = MASTER::Result.err("failed")
    refute result.ok?
    assert result.err?
    assert_equal "failed", result.error
  end

  def test_unwrap_returns_value_when_ok
    result = MASTER::Result.ok(42)
    assert_equal 42, result.unwrap
  end

  def test_unwrap_raises_when_err
    result = MASTER::Result.err("failed")
    assert_raises(RuntimeError) { result.unwrap }
  end

  def test_map_transforms_value_when_ok
    result = MASTER::Result.ok(2)
    mapped = result.map { |v| v * 2 }
    assert mapped.ok?
    assert_equal 4, mapped.value
  end

  def test_map_returns_error_when_err
    result = MASTER::Result.err("failed")
    mapped = result.map { |v| v * 2 }
    assert mapped.err?
    assert_equal "failed", mapped.error
  end

  def test_flat_map_chains_results_when_ok
    result = MASTER::Result.ok(2)
    chained = result.flat_map { |v| MASTER::Result.ok(v * 2) }
    assert chained.ok?
    assert_equal 4, chained.value
  end

  def test_flat_map_returns_error_when_err
    result = MASTER::Result.err("failed")
    chained = result.flat_map { |v| MASTER::Result.ok(v * 2) }
    assert chained.err?
    assert_equal "failed", chained.error
  end

  def test_try_captures_success
    result = MASTER::Result.try { 42 }
    assert result.ok?
    assert_equal 42, result.value
  end

  def test_try_captures_exception
    result = MASTER::Result.try { raise "boom" }
    assert result.err?
    assert_equal "boom", result.error
  end
end
