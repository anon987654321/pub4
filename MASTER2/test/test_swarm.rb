# frozen_string_literal: true

require_relative "test_helper"

class TestSwarm < Minitest::Test
  def test_responds_to_public_api
    assert_respond_to MASTER::Swarm, :coordinate
    assert_respond_to MASTER::Swarm, :agents
  end

  def test_swarm_module_exists
    assert defined?(MASTER::Swarm), "MASTER::Swarm should be defined"
  end
end
