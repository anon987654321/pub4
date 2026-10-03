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
      MASTER_KEYLESS MASTER_WEB_CHAT MASTER_NO_CLAUDE_CLI MASTER_NO_AGY_CLI MASTER_NO_OLLAMA
    ].to_h { |key| [key, ENV[key]] }
    @saved_env.each_key { |key| ENV.delete(key) }
    # Neutralize both local subscription CLIs so these tests grade keyless and
    # API-key routing in isolation from whichever CLI binary happens to be
    # installed on the machine running them. agy's own routing is covered by
    # test_agy_reachability.
    ENV["MASTER_NO_CLAUDE_CLI"] = "1"
    ENV["MASTER_NO_AGY_CLI"] = "1"
    # The Ollama daemon too: this Mac serves granite and qwen models that no
    # tier names, and they led chains these tests grade. Ollama tests opt in.
    ENV["MASTER_NO_OLLAMA"] = "1"
    @restore_routing = Master::TestSupport::RoutingIsolation.install
  end

  def local_ollama! = ENV.delete("MASTER_NO_OLLAMA")

  def teardown
    @restore_routing&.call
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
  # OLLAMA_BASE_URL, and a pulled model closes the chain. Ollama is on unless
  # MASTER_NO_OLLAMA says otherwise (8b29ed46d), so a daemon that cannot list
  # its models leaves the configured local chain standing, as it does with the
  # variable set.
  def test_local_tier_is_what_the_daemon_lists_and_closes_the_chain
    local_ollama!
    ENV["OPENROUTER_API_KEY"] = "sk-or-v1-#{'a' * 64}"
    ENV.delete("OLLAMA_BASE_URL")
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )
    router.define_singleton_method(:ollama_installed_models) { nil }
    assert_includes router.fallback_chain(task_type: :exploration), "ollama:gemma3:4b"

    router.define_singleton_method(:ollama_installed_models) { ["gemma3:4b"] }
    chain = router.fallback_chain(task_type: :exploration)
    assert_equal "ollama:gemma3:4b", chain.last
  ensure
    ENV.delete("OLLAMA_BASE_URL")
  end

  def test_local_tier_is_offered_once_ollama_base_url_is_set
    local_ollama!
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
    local_ollama!
    ENV["OPENROUTER_API_KEY"] = "sk-or-v1-#{'a' * 64}"
    ENV["OLLAMA_BASE_URL"] = "http://localhost:11434"
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )
    router.define_singleton_method(:ollama_installed_models) { ["llama3.2:3b", "nomic-embed-text:latest"] }

    local = router.fallback_chain(task_type: :exploration).grep(/\Aollama[:\/]/)
                  .reject { |id| id.end_with?(":cloud", "-cloud") }

    assert_equal ["ollama:llama3.2:3b"], local
  ensure
    ENV.delete("OLLAMA_BASE_URL")
  end

  # MASTER_NO_OLLAMA used to count only while the daemon was silent: with it
  # running, every pulled model joined the chain, and qwen2.5-coder:3b timed
  # out 1,046 times on this Mac while switched off.
  def test_ollama_switched_off_offers_no_ollama_lane_while_the_daemon_answers
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )
    router.define_singleton_method(:ollama_installed_models) { ["granite4.2:3b", "qwen2.5-coder:3b", "glm-5.3-flash:cloud"] }

    assert_empty router.fallback_chain(task_type: :chitchat).grep(/\Aollama[:\/]/)
    refute router.reachable?("ollama:granite4.2:3b")
  end

  # The hint is a command the operator runs, so it names the Ollama tag, not
  # MASTER's lane id: `ollama pull ollama:qwen3.5:35b` pulls nothing.
  def test_an_unpulled_model_hint_names_the_ollama_tag
    local_ollama!
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )
    router.define_singleton_method(:ollama_installed_models) { ["gemma3:4b"] }
    router.define_singleton_method(:ollama_enabled?) { true }

    assert_equal "ollama pull qwen3.5:35b", router.send(:ollama_problem, "ollama:qwen3.5:35b")
  end

  # Offline with no OLLAMA_BASE_URL the daemon is still asked, and a model
  # pulled outside models.yml ranks after the configured ones it holds.
  # Offline, a :cloud tag needs the network the session found missing, and a
  # model larger than the machine pages for every token.
  def test_local_models_offer_only_what_runs_on_this_machine
    local_ollama!
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
    local_ollama!
    ENV.delete("OLLAMA_BASE_URL")
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )
    router.define_singleton_method(:ollama_installed_models) do
      ["mistral:latest", "gemma3:4b", "nomic-embed-text:latest"]
    end

    assert_equal "http://localhost:11434", router.ollama_tags_base_url
    # The configured model first, then what else the daemon holds.
    assert_equal ["ollama:gemma3:4b", "ollama:mistral"], router.local_models

    router.define_singleton_method(:ollama_installed_models) { nil }
    # The tier is on without the variable (8b29ed46d), so a silent daemon leaves
    # the configured list standing; MASTER_NO_OLLAMA is what turns it off.
    assert_includes router.local_models, "ollama:gemma3:4b"
    ENV["MASTER_NO_OLLAMA"] = "1"
    assert_empty router.local_models, "a silent daemon offered models while the tier is off"
  end

  # The daemon's own answer, read over a real socket.
  def test_ollama_tags_are_read_from_the_daemon
    local_ollama!
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
    assert_match(/credit is spent/, router.unreachable_reason("anthropic/claude-opus-4.1"))
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
  # A hosted OpenAI-compatible endpoint lists more than it serves without a
  # key; the keyless rule picks what answers, and a key opens the rest.
  def test_a_hosted_endpoint_offers_its_keyless_models_until_a_key_is_set
    rows = [
      { "id" => "open-flash", "model_type" => "chat", "tier" => "turbo", "usage_based_only" => false },
      { "id" => "metered", "model_type" => "chat", "tier" => "turbo", "usage_based_only" => true },
      { "id" => "big-pro", "model_type" => "chat", "tier" => "pro", "usage_based_only" => false },
      { "id" => "painter", "model_type" => "image", "tier" => "turbo", "usage_based_only" => false },
    ]
    seen_auth = []
    server = TCPServer.new("127.0.0.1", 0)
    body = JSON.generate("data" => rows)
    thread = Thread.new do
      2.times do
        socket = server.accept
        headers = []
        headers << socket.gets.to_s.strip until headers.last == ""
        seen_auth << headers.find { |line| line.downcase.start_with?("authorization:") }
        socket.print("HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
        socket.close
      end
    end
    ENV.delete("MASTER_NO_POOL_PROBES")
    spec = { "base" => "http://127.0.0.1:#{server.addr[1]}/v1", "key_env" => ["HOSTED_TEST_KEY"],
             "keyless" => { "tier" => "turbo", "usage_based_only" => false } }
    build = lambda do
      router = Master::CLI::Routing::ModelRouter.new(config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT)
      router.instance_variable_get(:@rules)["openai_compatible"] = { "freehost" => spec }
      router.define_singleton_method(:start_pool_probes) { {} }
      router
    end

    keyless = build.call
    assert_equal ["freehost:open-flash"], keyless.hosted_models
    assert keyless.reachable?("freehost:open-flash")
    assert_equal "free", keyless.lane_label("freehost:open-flash")

    ENV["HOSTED_TEST_KEY"] = "sk-test"
    keyed = build.call
    assert_equal %w[freehost:open-flash freehost:metered freehost:big-pro], keyed.hosted_models
    assert_equal "sk-test", keyed.hosted_endpoint_for("freehost:big-pro")[:key]
    assert_nil seen_auth.first
    assert_equal "Authorization: Bearer sk-test", seen_auth.last
  ensure
    ENV.delete("HOSTED_TEST_KEY")
    ENV["MASTER_NO_POOL_PROBES"] = "1"
    thread&.kill
    server&.close
  end

  # Groq, Cerebras and NVIDIA wait in models.yml for a key; without one they
  # are not asked, so a boot does not spend a probe on each.
  def test_a_key_only_endpoint_is_not_asked_until_its_key_is_set
    ENV.delete("MASTER_NO_POOL_PROBES")
    asked = []
    router = Master::CLI::Routing::ModelRouter.new(config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT)
    router.instance_variable_get(:@rules)["openai_compatible"] = {
      "keyonly" => { "base" => "https://keyonly.invalid/v1", "key_env" => ["KEYONLY_TEST_KEY"] },
    }
    router.define_singleton_method(:get_json) { |url, **| asked << url; JSON.generate("data" => [{ "id" => "m" }]) }

    assert_empty router.hosted_models
    assert_empty asked

    ENV["KEYONLY_TEST_KEY"] = "sk-x"
    router.refresh_pool!
    assert_equal ["keyonly:m"], router.hosted_models
    assert_equal ["https://keyonly.invalid/v1/models"], asked
  ensure
    ENV.delete("KEYONLY_TEST_KEY")
    ENV["MASTER_NO_POOL_PROBES"] = "1"
  end

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
