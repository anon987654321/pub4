# frozen_string_literal: true

require_relative "test_helper"

# A /fix run forced through claude-cli reached the $10 session budget and
# refused every repair after it, though a subscription lane costs nothing
# per call. The estimate the circuit breaker charges is zero for such a lane.
class TestCliLaneCost < Minitest::Test
  def estimate(model) = Master::Review::LLMDispatcher.allocate.send(:estimate_cost, "x" * 40_000, model)

  def test_a_subscription_lane_costs_nothing_per_call
    assert_in_delta 0.0, estimate("claude-cli:claude-opus-5-5")
  end

  def test_an_api_lane_is_still_charged
    assert_operator estimate("openrouter/some-model"), :>, 0.0
  end
end
