# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/result"

class TestResult < Minitest::Test
  def test_ok_creation
    result = MASTER::Result.ok(42)
    assert result.ok?
    refute result.err?
    assert_equal 42, result.value
  end

  def test_err_creation
    result = MASTER::Result.err("error message")
    refute result.ok?
    assert result.err?
    assert_equal "error message", result.error
  end

  def test_unwrap_ok
    result = MASTER::Result.ok(42)
    assert_equal 42, result.unwrap
  end

  def test_unwrap_err_raises
    result = MASTER::Result.err("error")
    assert_raises(RuntimeError) { result.unwrap }
  end

  def test_map_ok
    result = MASTER::Result.ok(5).map { |x| x * 2 }
    assert result.ok?
    assert_equal 10, result.value
  end

  def test_map_err_passthrough
    result = MASTER::Result.err("error").map { |x| x * 2 }
    assert result.err?
    assert_equal "error", result.error
  end

  def test_flat_map_ok
    result = MASTER::Result.ok(5).flat_map { |x| MASTER::Result.ok(x * 2) }
    assert result.ok?
    assert_equal 10, result.value
  end

  def test_flat_map_err_passthrough
    result = MASTER::Result.err("error").flat_map { |x| MASTER::Result.ok(x * 2) }
    assert result.err?
    assert_equal "error", result.error
  end

  def test_flat_map_chain
    result = MASTER::Result.ok(5)
      .flat_map { |x| MASTER::Result.ok(x * 2) }
      .flat_map { |x| MASTER::Result.ok(x + 3) }
    assert result.ok?
    assert_equal 13, result.value
  end

  def test_flat_map_short_circuit
    result = MASTER::Result.ok(5)
      .flat_map { |x| MASTER::Result.err("error") }
      .flat_map { |x| MASTER::Result.ok(x + 3) }
    assert result.err?
    assert_equal "error", result.error
  end

  def test_try_success
    result = MASTER::Result.try { 42 }
    assert result.ok?
    assert_equal 42, result.value
  end

  def test_try_failure
    result = MASTER::Result.try { raise "error" }
    assert result.err?
    assert_match(/error/, result.error)
  end

  def test_module_shortcuts
    ok_result = MASTER.Ok(42)
    assert ok_result.ok?
    assert_equal 42, ok_result.value

    err_result = MASTER.Err("error")
    assert err_result.err?
    assert_equal "error", err_result.error
  end
end
