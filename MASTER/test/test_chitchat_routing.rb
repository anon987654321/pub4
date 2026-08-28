# frozen_string_literal: true

require_relative "test_helper"
require_relative "support/fake_config"

class TestChitchatRouting < Minitest::Test
  FakeConfig = Master::TestSupport::FakeConfig

  def test_models_yml_maps_chitchat_to_free_tier
    routes = Master.load_yaml(File.join(Master::ROOT, "data", "models.yml")).fetch("routes", {})
    assert_equal "free", routes["chitchat"]
  end

  def test_preferred_chitchat_selects_free_tier_model
    router = Master::CLI::Routing::ModelRouter.new(config: FakeConfig.new, root: Master::ROOT)
    chosen = router.preferred(task_type: :chitchat)
    free_ids = Array(router.send(:load_rules).dig("models", "free")).filter_map { |row| row["id"] }
    assert_includes free_ids, chosen, "chitchat should route to a free-tier model, got #{chosen}"
  end

  def test_greeting_classifies_as_chitchat
    router = Master::CLI::Routing::ModelRouter.new(config: FakeConfig.new, root: Master::ROOT)
    assert_equal :chitchat, router.classify_intent("hello!")
    assert_equal :chitchat, router.classify_intent("hey, how are you?")
  end

  def test_work_requests_stay_off_chitchat
    router = Master::CLI::Routing::ModelRouter.new(config: FakeConfig.new, root: Master::ROOT)
    assert_equal :code_generation, router.classify_intent("please implement a fix for the scanner")
    assert_equal :exploration, router.classify_intent("deploy the latest changes to production tonight")
  end

  def test_chitchat_intent_routes_to_free_tier
    router = Master::CLI::Routing::ModelRouter.new(config: FakeConfig.new, root: Master::ROOT)
    model = router.preferred_for("hello there")
    free_ids = Array(router.send(:load_rules).dig("models", "free")).filter_map { |row| row["id"] }
    keyless_ids = Array(router.send(:load_rules).dig("ferrum_web_chat", "free_latest"))
    assert_includes(free_ids + keyless_ids, model)
  end

  def test_chitchat_fallback_chain_prefers_free_or_keyless_head
    router = Master::CLI::Routing::ModelRouter.new(config: FakeConfig.new, root: Master::ROOT)
    free_ids = Array(router.send(:load_rules).dig("models", "free")).filter_map { |row| row["id"] }
    keyless_ids = Array(router.send(:load_rules).dig("ferrum_web_chat", "free_latest"))
    allowed = free_ids + keyless_ids
    chain = router.fallback_chain(task_type: :chitchat)
    assert chain.any?, "expected non-empty fallback chain"
    assert_includes allowed, chain.first
  end
end
