# frozen_string_literal: true

require_relative "test_helper"

class TestAuthProfileLane < Minitest::Test
  def test_load_lanes_sorted_by_priority
    lanes = Master::Ground::AuthProfileLane.load_lanes
    assert lanes.is_a?(Array)
    priorities = lanes.map { |l| l["priority"].to_i }
    assert_equal priorities.sort, priorities
  end

  def test_models_for_router_merges_primary
    router = Object.new
    router.define_singleton_method(:primary_models) { ["x-ai/grok-4.3"] }
    models = Master::Ground::AuthProfileLane.models_for_router(router)
    assert_includes models, "x-ai/grok-4.3"
  end
end