# frozen_string_literal: true

require_relative "test_helper"

class TestResult < Minitest::Test
  def test_ok_result
    result = MASTER::Result.ok("success")
    assert result.ok?
    refute result.err?
    assert_equal "success", result.value
  end

  def test_err_result
    result = MASTER::Result.err("failure")
    assert result.err?
    refute result.ok?
    assert_equal "failure", result.error
  end

  def test_flat_map_on_ok
    result = MASTER::Result.ok(5)
                           .flat_map { |v| MASTER::Result.ok(v * 2) }
    assert result.ok?
    assert_equal 10, result.value
  end

  def test_flat_map_on_err
    result = MASTER::Result.err("failed")
                           .flat_map { |v| MASTER::Result.ok(v * 2) }
    assert result.err?
    assert_equal "failed", result.error
  end

  def test_map_on_ok
    result = MASTER::Result.ok(5).map { |v| v * 2 }
    assert result.ok?
    assert_equal 10, result.value
  end

  def test_map_on_err
    result = MASTER::Result.err("failed").map { |v| v * 2 }
    assert result.err?
    assert_equal "failed", result.error
  end

  def test_value_or_default
    ok_result = MASTER::Result.ok("value")
    err_result = MASTER::Result.err("error")

    assert_equal "value", ok_result.value_or("default")
    assert_equal "default", err_result.value_or("default")
  end

  def test_chain_multiple_operations
    result = MASTER::Result.ok(1)
                           .flat_map { |v| MASTER::Result.ok(v + 1) }
                           .flat_map { |v| MASTER::Result.ok(v * 3) }
                           .flat_map { |v| MASTER::Result.ok(v.to_s) }

    assert result.ok?
    assert_equal "6", result.value
  end

  def test_chain_stops_on_error
    result = MASTER::Result.ok(1)
                           .flat_map { |v| MASTER::Result.ok(v + 1) }
                           .flat_map { |_| MASTER::Result.err("stopped") }
                           .flat_map { |v| MASTER::Result.ok(v * 3) }

    assert result.err?
    assert_equal "stopped", result.error
  end
end
