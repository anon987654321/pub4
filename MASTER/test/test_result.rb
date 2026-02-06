# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/result"

module MASTER
  class TestResult < Minitest::Test
    def test_ok_creates_success_result
      result = Result.ok(42)
      assert result.ok?
      refute result.err?
      assert_equal 42, result.value
      assert_nil result.error
    end

    def test_err_creates_error_result
      result = Result.err("failure")
      assert result.err?
      refute result.ok?
      assert_equal "failure", result.error
      assert_nil result.value
    end

    def test_unwrap_returns_value_on_ok
      result = Result.ok(99)
      assert_equal 99, result.unwrap
    end

    def test_unwrap_raises_on_err
      result = Result.err("boom")
      assert_raises(RuntimeError) { result.unwrap }
    end

    def test_map_transforms_ok_value
      result = Result.ok(10).map { |v| v * 2 }
      assert result.ok?
      assert_equal 20, result.value
    end

    def test_map_preserves_err
      result = Result.err("fail").map { |v| v * 2 }
      assert result.err?
      assert_equal "fail", result.error
    end

    def test_map_catches_exceptions
      result = Result.ok(10).map { |v| raise "boom" }
      assert result.err?
      assert_equal "boom", result.error
    end

    def test_flat_map_chains_ok_results
      result = Result.ok(5).flat_map { |v| Result.ok(v * 3) }
      assert result.ok?
      assert_equal 15, result.value
    end

    def test_flat_map_stops_on_err
      result = Result.ok(5).flat_map { |v| Result.err("stop") }
      assert result.err?
      assert_equal "stop", result.error
    end

    def test_flat_map_preserves_initial_err
      result = Result.err("initial").flat_map { |v| Result.ok(v * 2) }
      assert result.err?
      assert_equal "initial", result.error
    end

    def test_flat_map_catches_exceptions
      result = Result.ok(10).flat_map { |v| raise "boom" }
      assert result.err?
      assert_equal "boom", result.error
    end

    def test_try_wraps_success
      result = Result.try { 42 }
      assert result.ok?
      assert_equal 42, result.value
    end

    def test_try_wraps_exception
      result = Result.try { raise "error" }
      assert result.err?
      assert_equal "error", result.error
    end

    def test_module_shortcuts
      result = MASTER.Ok(123)
      assert result.ok?
      assert_equal 123, result.value

      result = MASTER.Err("fail")
      assert result.err?
      assert_equal "fail", result.error
    end
  end
end
