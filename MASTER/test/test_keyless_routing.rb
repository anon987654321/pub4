# frozen_string_literal: true

require_relative "test_helper"
require_relative "support_fake_config"

class TestKeylessRouting < Minitest::Test
  FakeConfig = Master::TestSupport::FakeConfig

  def setup
    @saved_env = %w[
      XAI_API_KEY OPENROUTER_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY
      DEEPSEEK_API_KEY GOOGLE_API_KEY GEMINI_API_KEY MISTRAL_API_KEY
      MASTER_KEYLESS MASTER_WEB_CHAT MASTER_NO_CLAUDE_CLI MASTER_NO_AGY_CLI
    ].to_h { |key| [key, ENV[key]] }
    @saved_env.each_key { |key| ENV.delete(key) }
    # Neutralize both local subscription CLIs so these tests grade keyless and
    # API-key routing in isolation from whichever CLI binary happens to be
    # installed on the machine running them. agy's own routing is covered by
    # test_agy_reachability.
    ENV["MASTER_NO_CLAUDE_CLI"] = "1"
    ENV["MASTER_NO_AGY_CLI"] = "1"
  end

  def teardown
    @saved_env.each { |key, val| val.nil? ? ENV.delete(key) : ENV[key] = val }
  end

  def test_default_model_is_web_chat_grok_without_keys
    assert_equal "web-chat:grok", Master.default_model
    assert Master.keyless_llm_enabled?
  end

  def test_default_model_prefers_grok_api_with_xai_key
    ENV["XAI_API_KEY"] = "xai-" + ("a" * 32)
    assert_equal "grok-4.3", Master.default_model
    refute Master.keyless_llm_enabled?
  end

  def test_router_injects_web_chat_models_when_keyless
    ENV["MASTER_NO_CLAUDE_CLI"] = "1"
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: "web-chat:grok"), root: Master::ROOT,
    )
    assert router.web_chat_enabled?
    assert router.keyless_mode?
    chain = router.fallback_chain(task_type: :exploration)
    assert_equal "web-chat:grok", chain.first
    assert_includes chain, "web-chat:chatgpt"
    assert_includes chain, "web-chat:kimi"
  end

  def test_router_prefers_free_chain_when_openrouter_key_present
    ENV["OPENROUTER_API_KEY"] = "sk-or-v1-" + ("a" * 64)
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )
    refute router.keyless_mode?
    chain = router.fallback_chain(task_type: :exploration)
    assert_equal "nvidia/nemotron-3-super-120b-a12b:free", chain.first
  end

  def test_web_chat_disabled_when_keys_present_without_opt_in
    ENV["OPENROUTER_API_KEY"] = "sk-or-v1-" + ("a" * 64)
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )
    refute router.web_chat_enabled?
    refute_includes router.fallback_chain(task_type: :exploration), "web-chat:grok"
  end

  def test_web_chat_enabled_with_master_web_chat_even_when_keys_present
    ENV["OPENROUTER_API_KEY"] = "sk-or-v1-" + ("a" * 64)
    ENV["MASTER_WEB_CHAT"] = "1"
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )
    assert router.web_chat_enabled?
    assert_includes router.fallback_chain(task_type: :exploration), "web-chat:grok"
  end
end
