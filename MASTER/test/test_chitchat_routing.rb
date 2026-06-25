# frozen_string_literal: true

require_relative "test_helper"

class TestChitchatRouting < Minitest::Test
  class FakeConfig
    def initialize(model = "z-ai/glm-4.5-air:free")
      @model = model
    end

    attr_reader :model
  end

  def test_models_yml_maps_chitchat_to_free_tier
    routes = Master.load_yaml(File.join(Master::ROOT, "data", "models.yml")).fetch("routes", {})
    assert_equal "free", routes["chitchat"]
  end

  def test_preferred_chitchat_selects_free_tier_model
    router = Master::Now::Routing::ModelRouter.new(config: FakeConfig.new, root: Master::ROOT)
    chosen = router.preferred(task_type: :chitchat)
    free_ids = Array(router.send(:load_rules).dig("models", "free")).filter_map { |row| row["id"] }
    assert_includes free_ids, chosen, "chitchat should route to a free-tier model, got #{chosen}"
  end

  def test_casual_text_defaults_to_exploration_intent
    router = Master::Now::Routing::ModelRouter.new(config: FakeConfig.new, root: Master::ROOT)
    assert_equal :exploration, router.classify_intent("hey, how are you?")
  end

  def test_exploration_and_chitchat_share_free_tier
    router = Master::Now::Routing::ModelRouter.new(config: FakeConfig.new, root: Master::ROOT)
    exploration = router.preferred(task_type: :exploration)
    chitchat = router.preferred(task_type: :chitchat)
    assert_equal exploration, chitchat
  end

  def test_chitchat_fallback_chain_prefers_free_or_keyless_head
    router = Master::Now::Routing::ModelRouter.new(config: FakeConfig.new, root: Master::ROOT)
    free_ids = Array(router.send(:load_rules).dig("models", "free")).filter_map { |row| row["id"] }
    keyless_ids = Array(router.send(:load_rules).dig("ferrum_web_chat", "free_latest"))
    allowed = free_ids + keyless_ids
    chain = router.fallback_chain(task_type: :chitchat)
    assert chain.any?, "expected non-empty fallback chain"
    assert_includes allowed, chain.first
  end
end