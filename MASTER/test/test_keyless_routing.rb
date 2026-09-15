# frozen_string_literal: true

require_relative "test_helper"
require_relative "support_fake_config"
require "json"
require "socket"

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

  # The local tier is whatever the daemon holds, with or without
  # OLLAMA_BASE_URL: a pulled model closes the chain, and a machine whose daemon
  # is silent offers no ollama id at all, so none can answer "no model".
  def test_local_tier_is_what_the_daemon_lists_and_closes_the_chain
    ENV["OPENROUTER_API_KEY"] = "sk-or-v1-#{'a' * 64}"
    ENV.delete("OLLAMA_BASE_URL")
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )
    router.define_singleton_method(:ollama_installed_models) { nil }
    assert_empty router.fallback_chain(task_type: :exploration).grep(/\Aollama[:\/]/)

    router.define_singleton_method(:ollama_installed_models) { ["gemma3:4b"] }
    chain = router.fallback_chain(task_type: :exploration)
    assert_equal "ollama:gemma3:4b", chain.last
  ensure
    ENV.delete("OLLAMA_BASE_URL")
  end

  def test_local_tier_is_offered_once_ollama_base_url_is_set
    ENV["OPENROUTER_API_KEY"] = "sk-or-v1-#{'a' * 64}"
    ENV["OLLAMA_BASE_URL"] = "http://localhost:11434/v1"
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )

    # A daemon that cannot list its models leaves the configured chain standing.
    router.define_singleton_method(:ollama_installed_models) { nil }

    assert router.ollama_enabled?
    refute_empty router.fallback_chain(task_type: :exploration).grep(/\Aollama[:\/]/)
  ensure
    ENV.delete("OLLAMA_BASE_URL")
  end

  # models.yml names three local models and nothing checked any was pulled; a
  # missing one answered "no model" and the chain fell through to a paid lane.
  def test_local_tier_offers_only_the_models_the_daemon_holds
    ENV["OPENROUTER_API_KEY"] = "sk-or-v1-#{'a' * 64}"
    ENV["OLLAMA_BASE_URL"] = "http://localhost:11434"
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )
    router.define_singleton_method(:ollama_installed_models) { ["llama3.2:3b", "nomic-embed-text:latest"] }

    local = router.fallback_chain(task_type: :exploration).grep(/\Aollama[:\/]/)

    assert_equal ["ollama:llama3.2:3b"], local
  ensure
    ENV.delete("OLLAMA_BASE_URL")
  end

  # Offline with no OLLAMA_BASE_URL the daemon is still asked, and a model
  # pulled outside models.yml ranks after the configured ones it holds.
  # Offline, a :cloud tag needs the network the session found missing, and a
  # model larger than the machine pages for every token.
  def test_local_models_offer_only_what_runs_on_this_machine
    router = Master::CLI::Routing::ModelRouter.new(config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT)
    router.define_singleton_method(:ollama_installed_models) { %w[glm-5.3-flash:cloud gemma3:4b gemma4:26b llama3:latest] }
    router.instance_variable_set(:@ollama_sizes, { "glm-5.3-flash:cloud" => 317, "gemma3:4b" => 3_338_801_804,
                                                   "gemma4:26b" => 18_604_148_513, "llama3:latest" => 4_661_224_676 })

    Master::Core::Memory.stub(:host_memory_mb, 8192) do
      assert_equal %w[ollama:gemma3:4b ollama:llama3], router.local_models
      refute router.reachable?("ollama:gemma4:26b")
      assert router.reachable?("ollama:glm-5.3-flash:cloud")
    end
  end

  def test_local_models_rank_what_the_daemon_holds_without_the_env_gate
    ENV.delete("OLLAMA_BASE_URL")
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )
    router.define_singleton_method(:ollama_installed_models) do
      ["mistral:latest", "qwen2.5-coder:3b", "nomic-embed-text:latest"]
    end

    assert_equal "http://localhost:11434", router.ollama_tags_base_url
    assert_equal ["ollama:qwen2.5-coder:3b", "ollama:mistral"], router.local_models

    router.define_singleton_method(:ollama_installed_models) { nil }
    assert_empty router.local_models, "a silent daemon offered models while the tier is off"
  end

  # The daemon's own answer, read over a real socket.
  def test_ollama_tags_are_read_from_the_daemon
    server = TCPServer.new("127.0.0.1", 0)
    body = JSON.generate("models" => [{ "name" => "phi4:mini" }, { "name" => "qwen2.5-coder:7b" }])
    thread = Thread.new do
      socket = server.accept
      nil until socket.gets.to_s.strip.empty?
      socket.print("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\n" \
                   "Connection: close\r\n\r\n#{body}")
      socket.close
    end
    ENV["OLLAMA_BASE_URL"] = "http://127.0.0.1:#{server.addr[1]}/v1"
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )

    assert_equal ["phi4:mini", "qwen2.5-coder:7b"], router.ollama_installed_models
    assert router.ollama_pulled?("ollama:phi4:mini")
    refute router.ollama_pulled?("ollama:llama3.2:3b")
  ensure
    thread&.kill
    server&.close
    ENV.delete("OLLAMA_BASE_URL")
  end

  # gemini-2.5-flash is Google's own endpoint; with only an OpenRouter key the
  # session chose it, every call failed, and the error claimed no LLM was wired.
  def test_a_model_whose_key_is_unset_leaves_the_pool_naming_the_key
    ENV["OPENROUTER_API_KEY"] = "sk-or-v1-#{'a' * 64}"
    router = Master::CLI::Routing::ModelRouter.new(config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT)
    router.define_singleton_method(:ollama_installed_models) { [] }

    assert_match(/GEMINI_API_KEY/, router.unreachable_reason("gemini-2.5-flash"))
    assert router.reachable?("google/gemini-2.5-flash")
    refute_includes router.fallback_chain(task_type: :exploration), "gemini-2.5-flash"
    assert_match(/GEMINI_API_KEY/, router.pool_growth.first)
  end

  def test_spent_openrouter_credit_keeps_the_free_models_and_drops_the_paid
    ENV["OPENROUTER_API_KEY"] = "sk-or-v1-#{'a' * 64}"
    router = Master::CLI::Routing::ModelRouter.new(config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT)
    router.define_singleton_method(:probe_value) { |name, wait:| name == "openrouter_credits" ? false : nil }

    assert router.reachable?("nvidia/nemotron-3-super-120b-a12b:free")
    assert_match(/credit is spent/, router.unreachable_reason("anthropic/claude-opus-4"))
  end

  def test_a_cli_lane_joins_when_signed_in_and_names_its_login_when_not
    router = Master::CLI::Routing::ModelRouter.new(config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT)
    router.define_singleton_method(:executable_on_path?) { |_binary| true }
    signed_in = false
    router.define_singleton_method(:probe_value) { |_name, wait:| signed_in }

    assert_equal "run codex login", router.unreachable_reason("codex-cli:auto")
    signed_in = true
    assert router.reachable?("codex-cli:auto")
    assert_equal "codex", router.cli_lane("codex-cli:auto")["binary"]
  end

  # mistral.rs, LM Studio and llama-server all answer the OpenAI /models call.
  def test_a_local_server_puts_the_models_it_lists_in_the_pool
    server = TCPServer.new("127.0.0.1", 0)
    body = JSON.generate("data" => [{ "id" => "Qwen/Qwen3-4B" }])
    thread = Thread.new do
      socket = server.accept
      nil until socket.gets.to_s.strip.empty?
      socket.print("HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      socket.close
    end
    ENV.delete("MASTER_NO_POOL_PROBES")
    router = Master::CLI::Routing::ModelRouter.new(config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT)
    base = "http://127.0.0.1:#{server.addr[1]}/v1"
    router.instance_variable_get(:@rules)["local_servers"] = [base]
    router.define_singleton_method(:start_pool_probes) { {} }

    assert_equal base, router.local_server_for("local:Qwen/Qwen3-4B")
    assert router.reachable?("local:Qwen/Qwen3-4B")
  ensure
    ENV["MASTER_NO_POOL_PROBES"] = "1"
    thread&.kill
    server&.close
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
