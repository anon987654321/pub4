# frozen_string_literal: true

require "test_helper"
require_relative "../gates/lib/server_response_budget"

class TestServerResponseBudget < Minitest::Test
  def test_percentile_is_the_declared_p95
    gate = Deploy::ServerResponseBudgetGate.allocate
    assert_equal 95, gate.send(:percentile, (1..100).to_a)
    assert_equal 1, gate.send(:percentile, [1])
  end

  def test_default_budget_is_conservative_and_explicit
    gate = Deploy::ServerResponseBudgetGate.allocate
    assert_equal 1500, gate.send(:limits).fetch("p95_ms")
    assert_equal 1_048_576, gate.send(:limits).fetch("p95_bytes")
  end
end
