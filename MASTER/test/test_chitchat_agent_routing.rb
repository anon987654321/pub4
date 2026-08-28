# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/fake_config"

class TestChitchatAgentRouting < Minitest::Test
  FakeConfig = Master::TestSupport::FakeConfig

  def setup
    @router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new,
      root: Master::ROOT,
    )
    @agent = Master::Review::Agent.allocate
    @agent.instance_variable_set(:@model_router, @router)
    @agent.instance_variable_set(:@config, FakeConfig.new)
    @agent.instance_variable_set(:@homeostat, nil)
    @agent.instance_variable_set(:@bus, nil)
  end

  def test_routed_models_classifies_greeting_as_chitchat
    models = @agent.send(:routed_models, "hey, how are you?")
    free_ids = Array(@router.send(:load_rules).dig("models", "free")).filter_map { |row| row["id"] }
    keyless_ids = Array(@router.send(:load_rules).dig("ferrum_web_chat", "free_latest"))
    assert_includes free_ids + keyless_ids, models.first
  end

  def test_routed_models_honors_explicit_task_type
    models = @agent.send(:routed_models, "hello", task_type: :code_generation)
    refute_equal :chitchat, @router.classify_intent("please implement a fix")
    assert models.any?
  end

  def test_routed_models_work_request_avoids_chitchat_head
    models = @agent.send(:routed_models, "please implement a fix for the scanner")
    refute_equal :chitchat, @router.classify_intent("please implement a fix for the scanner")
    assert models.any?
  end
end
