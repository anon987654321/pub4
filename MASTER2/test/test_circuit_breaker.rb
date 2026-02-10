# frozen_string_literal: true

require_relative "test_helper"

class TestCircuitBreaker < Minitest::Test
  def test_responds_to_public_api
    breaker = MASTER::CircuitBreaker.new
    assert_respond_to breaker, :call
    assert_respond_to breaker, :open?
    assert_respond_to breaker, :reset
  end

  def test_circuit_breaker_class_exists
    assert defined?(MASTER::CircuitBreaker), "MASTER::CircuitBreaker should be defined"
  end
end
