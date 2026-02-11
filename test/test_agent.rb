# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestAgent < Minitest::Test
  def setup
    MASTER::DB.setup(path: ":memory:")
  end

  def test_agent_creation
    agent = MASTER::Agent.new(task: { text: "test" }, budget: 2.50, scope: "rails")
    assert_equal "rails", agent.scope
    assert_equal :pending, agent.status
    assert_equal 2.50, agent.budget
    assert_match(/^[0-9a-f]{16}$/, agent.id)
  end

  def test_user_agent_string
    agent = MASTER::Agent.new(task: { text: "test" }, budget: 2.50, scope: "rails")
    ua = agent.user_agent
    assert_match(/MASTER\/#{MASTER::VERSION}/, ua)
    assert_match(/agent:#{agent.id}/, ua)
    assert_match(/scope:rails/, ua)
    assert_match(/budget:\$2\.50/, ua)
  end

  def test_agent_run
    agent = MASTER::Agent.new(task: { text: "test" }, budget: 5.00)
    result = agent.run
    # Agent should complete the run even if pipeline fails
    assert [:completed, :failed].include?(agent.status)
    assert result # Result should be set
    assert agent.elapsed > 0
  end

  def test_agent_to_h
    agent = MASTER::Agent.new(task: { text: "test" }, budget: 2.50, scope: "security")
    h = agent.to_h
    assert_equal "security", h[:scope]
    assert_equal :pending, h[:status]
  end
end
