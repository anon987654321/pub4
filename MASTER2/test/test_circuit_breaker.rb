# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestCircuitBreaker < Minitest::Test
  def test_rate_limit_state_initialized
    state = MASTER::CircuitBreaker.rate_limit_state
    assert state.key?(:requests)
    assert state.key?(:window_start)
    assert_kind_of Array, state[:requests]
    assert_kind_of Time, state[:window_start]
  end

  def test_circuit_closed_when_stoplight_unavailable
    skip "Stoplight is available" if STOPLIGHT_AVAILABLE
    result = MASTER::CircuitBreaker.circuit_closed?("test-model")
    assert result, "Circuit should be closed when stoplight unavailable"
  end

  def test_run_executes_block
    result = MASTER::CircuitBreaker.run("test-model") { "success" }
    assert_equal "success", result
  end

  def test_run_propagates_errors
    assert_raises(StandardError) do
      MASTER::CircuitBreaker.run("test-model") { raise StandardError, "test error" }
    end
  end

  def test_constants_defined
    assert_equal 3, MASTER::CircuitBreaker::FAILURES_BEFORE_TRIP
    assert_equal 300, MASTER::CircuitBreaker::CIRCUIT_RESET_SECONDS
    assert_equal 30, MASTER::CircuitBreaker::RATE_LIMIT_PER_MINUTE
  end

  def test_stoplight_constant_is_boolean
    assert [true, false].include?(STOPLIGHT_AVAILABLE)
  end
end
