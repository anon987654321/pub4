# frozen_string_literal: true

require "minitest/autorun"
module Master; module Core; module Routing; end; end; end

require_relative "../lib/core/routing/model_passport"
require_relative "../lib/core/routing/model_control_plane"
require_relative "../lib/core/routing/capability/capability_map"

# Mock Router
class MockRouter
  def preferred(task_type: nil); "gemma-4"; end
end

class TestModelControlPlane < Minitest::Test
  def setup
    @catalog = Struct.new(:resolve).new(->(n) { n })
    @cap_map = Master::Core::Routing::CapabilityMap.new
    @router = MockRouter.new
    @plane = Master::Core::Routing::ModelControlPlane.new(
      catalog: @catalog,
      capability_map: @cap_map,
      router: @router
    )
  end

  def test_route_selection
    reqs = { task_type: :coding, budget: :low }
    route = @plane.select_route(task_requirements: reqs)
    
    assert_equal "gemma-4", route[:primary]
    assert_match(/Selected based on empirical capability/, route[:rationale])
  end

  def test_passport_structure
    passport = Master::Core::Routing::ModelPassport.new(
      identity: "gemma-4",
      provider: "google",
      execution: :cloud,
      capabilities: { coding: 0.9 }
    )
    assert_equal :cloud, passport.execution
    assert_equal 0.9, passport.capabilities[:coding]
  end
end
