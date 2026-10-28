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
      MASTER_KEYLESS MASTER_WEB_CHAT MASTER_NO_WEB_CHAT MASTER_LOCAL_ONLY MASTER_NO_CLAUDE_CLI MASTER_NO_GROK_CLI MASTER_NO_AGY_CLI MASTER_NO_OLLAMA
      MASTER_NO_POOL_PROBES MASTER_LLM_GATEWAY_URL MASTER_LLM_GATEWAY_KEY FREELLMPOOL_PROXY_KEY
    ].to_h { |key| [key, ENV[key]] }
    @saved_env.each_key { |key| ENV.delete(key) }
    # Neutralize both local subscription CLIs so these tests grade keyless and
    # API-key routing in isolation from whichever CLI binary happens to be
    # installed on the machine running them. agy's own routing is covered by
    # test_agy_reachability.
    ENV["MASTER_NO_CLAUDE_CLI"] = "1"
    ENV["MASTER_NO_GROK_CLI"] = "1"
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
    assert_equal chain, router.send(:priority_fallback_order, chain)
    assert_includes chain, "web-chat:grok"
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
    assert_includes chain, "nvidia/nemotron-3-super-120b-a12b:free"
    assert_equal chain, router.send(:priority_fallback_order, chain)
  end

  # The local tier is whatever the daemon holds, with or without
  # OLLAMA_BASE_URL, and a pulled model closes the chain. Ollama is on unless
  # MASTER_NO_OLLAMA says otherwise, so a daemon that cannot list
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

  # models.yml names local models the daemon may not hold; an unpulled one answers
  # "no model" and the chain falls through to a paid lane.
  def test_local_tier_offers_only_the_models_the_daemon_holds
    local_ollama!
    ENV["OPENROUTER_API_KEY"] = "sk-or-v1-#{'a' * 64}"
    ENV["OLLAMA_BASE_URL"] = "http://localhost:11434"
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )
    router.define_singleton_method(:ollama_installed_models) { ["llama3.2:3b", "nomic-embed-text:latest"] }

    local = router.fallback_chain(task_type: :exploration).grep(/\Aollama[:\/]/)

    assert_empty local, "only allowlisted local Gemma may enter the fallback tier"
  ensure
    ENV.delete("OLLAMA_BASE_URL")
  end

  # Cloud IDs are rejected outright; only the explicitly allowlisted local Gemma is eligible.
  def test_cloud_models_are_unsupported_and_only_local_gemma_is_allowed
    local_ollama!
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )
    router.define_singleton_method(:ollama_installed_models) do
      ["glm-5.3-flash:cloud", "gemma3:4b", "qwen2.5-coder:3b", "granite4.2:3b"]
    end
    router.define_singleton_method(:ollama_size) { |_name| 0 }

    cloud = "ollama:glm-5.3-flash:cloud"
    assert_equal ["ollama:gemma3:4b"], router.local_models
    assert_cloud_rejected(router, cloud)
    refute_includes router.fallback_chain(task_type: :exploration), "ollama:qwen2.5-coder:3b"
    refute_includes router.fallback_chain(task_type: :exploration), "ollama:granite4.2:3b"
    ollama_fallbacks = router.fallback_chain(task_type: :exploration).grep(/\Aollama[:\/]/).uniq
    assert_equal ["ollama:gemma3:4b"], ollama_fallbacks
  end

  CLOUD_UNSUPPORTED = "ollama cloud models are unsupported"

  # The code rule on its own, then whatever data/lanes.yml hand-kills ahead of
  # it: a dead entry names itself, so the reason follows the list, not a name here.
  def assert_cloud_rejected(router, cloud)
    Master::Io::LaneQuota.stub(:manual_dead, []) do
      assert_equal CLOUD_UNSUPPORTED, router.unreachable_reason(cloud)
    end

    dead = Master::Io::LaneQuota.manual_dead(Master.load_yaml(Master::Io::LaneQuota::DATA))
    hand_killed = dead.find { |lane| cloud.start_with?(lane) }
    expected = hand_killed ? "#{hand_killed}: dead by hand (data/lanes.yml dead:)" : CLOUD_UNSUPPORTED
    assert_equal expected, router.unreachable_reason(cloud)
    refute router.reachable?(cloud)
  end

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

  # Only the configured Gemma fallback is eligible; other installed models
  # and remotely executed :cloud models must not enter the local pool.
  def test_local_models_offer_only_what_runs_on_this_machine
    local_ollama!
    router = Master::CLI::Routing::ModelRouter.new(config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT)
    router.define_singleton_method(:ollama_installed_models) { %w[glm-5.3-flash:cloud gemma3:4b gemma4:26b llama3:latest] }
    router.instance_variable_set(:@ollama_sizes, { "glm-5.3-flash:cloud" => 317, "gemma3:4b" => 3_338_801_804,
                                                   "gemma4:26b" => 18_604_148_513, "llama3:latest" => 4_661_224_676 })

    # Cloud routing is disabled independently of the local Gemma fallback.
    Master::Io::LaneQuota.stub(:manual_dead, []) do
      Master::Core::Memory.stub(:host_memory_mb, 8192) do
        assert_equal ["ollama:gemma3:4b"], router.local_models
        refute router.reachable?("ollama:gemma4:26b")
        refute router.reachable?("ollama:glm-5.3-flash:cloud")
      end
    end
  end

  def test_local_models_obey_the_allowlist_without_the_env_check
    local_ollama!
    ENV.delete("OLLAMA_BASE_URL")
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )
    router.define_singleton_method(:ollama_installed_models) do
      ["mistral:latest", "gemma3:4b", "nomic-embed-text:latest"]
    end

    assert_equal "http://localhost:11434", router.ollama_tags_base_url
    # The explicit allowlist is the local fallback policy, not a ranking hint.
    assert_equal ["ollama:gemma3:4b"], router.local_models

    router.define_singleton_method(:ollama_installed_models) { nil }
    # A silent daemon leaves the allowlisted Gemma fallback standing;
    # MASTER_NO_OLLAMA still disables the whole local lane.
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

  # gemini-2.5-flash is Google's own endpoint; with only an OpenRouter key it must
  # leave the pool and name the missing key, not fail every call.
  def test_a_model_whose_key_is_unset_leaves_the_pool_naming_the_key
    ENV["OPENROUTER_API_KEY"] = "sk-or-v1-#{'a' * 64}"
    router = Master::CLI::Routing::ModelRouter.new(config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT)
    router.define_singleton_method(:ollama_installed_models) { [] }

    # Manual kills in data/lanes.yml are stubbed out; this test grades the missing-key reason.
    Master::Io::LaneQuota.stub(:manual_dead, []) do
      assert_match(/GEMINI_API_KEY/, router.unreachable_reason("gemini-2.5-flash"))
      assert router.reachable?("google/gemini-2.5-flash")
      refute_includes router.fallback_chain(task_type: :exploration), "gemini-2.5-flash"
      assert_match(/GEMINI_API_KEY/, router.pool_growth.first)
    end
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

    assert_equal "run grok login", router.unreachable_reason("grok-cli:auto")
    signed_in = true
    assert router.reachable?("grok-cli:auto")
    assert_equal "grok", router.cli_lane("grok-cli:auto")["binary"]
  end

  def test_manually_dead_codex_lane_stays_out_of_the_pool_when_login_succeeds
    ENV["MASTER_NO_POOL_PROBES"] = "1"
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )
    router.define_singleton_method(:executable_on_path?) { |_binary| true }
    router.define_singleton_method(:probe_value) { |_name, wait:| true }

    assert_includes Master::Io::LaneQuota.manual_dead, "codex-cli"
    refute router.reachable?("codex-cli:auto")
    refute_includes router.fallback_chain(task_type: :code_generation), "codex-cli:auto"
    refute_includes router.pool, "codex-cli:auto"
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
             "keyless_max_concurrency" => 1, "quota_bucket" => "freehost-account",
             "keyless" => { "tier" => "turbo", "usage_based_only" => false } }
    build = lambda do
      router = Master::CLI::Routing::ModelRouter.new(config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT)
      router.instance_variable_get(:@rules)["openai_compatible"] = { "freehost" => spec }
      router.define_singleton_method(:start_pool_probes) { {} }
      router
    end

    keyless = build.call
    assert_equal ["freehost:open-flash"], keyless.hosted_models
    assert_equal 1, keyless.hosted_endpoint_for("freehost:open-flash")[:max_concurrency]
    assert_equal "freehost-account", keyless.hosted_endpoint_for("freehost:open-flash")[:quota_bucket]
    assert keyless.reachable?("freehost:open-flash")
    assert_equal "free", keyless.lane_label("freehost:open-flash")

    ENV["HOSTED_TEST_KEY"] = "sk-test"
    keyed = build.call
    assert_equal %w[freehost:open-flash freehost:metered freehost:big-pro], keyed.hosted_models
    assert_equal "sk-test", keyed.hosted_endpoint_for("freehost:big-pro")[:key]
    assert_nil keyed.hosted_endpoint_for("freehost:big-pro")[:max_concurrency]
    assert_nil seen_auth.first
    assert_equal "Authorization: Bearer sk-test", seen_auth.last
  ensure
    ENV.delete("HOSTED_TEST_KEY")
    ENV["MASTER_NO_POOL_PROBES"] = "1"
    thread&.kill
    server&.close
  end

  # A local or explicitly trusted OpenAI-compatible gateway joins the
  # existing pool only after its URL is set. The URL's host and model ids are
  # discovered through the same endpoint catalogue used by other hosted lanes.
  def test_opt_in_gateway_models_join_the_existing_fallback_pool
    rows = [{ "id" => "pool-model", "model_type" => "chat" }]
    body = JSON.generate("data" => rows)
    seen = []
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      2.times do
        socket = server.accept
        request = socket.gets.to_s.strip
        headers = []
        headers << socket.gets.to_s.strip until headers.last == ""
        seen << [request, headers]
        socket.print("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")

        socket.close
      end
    end

    ENV["MASTER_LLM_GATEWAY_URL"] = "http://127.0.0.1:#{server.addr[1]}/v1"
    ENV.delete("MASTER_LLM_GATEWAY_KEY")
    ENV.delete("FREELLMPOOL_PROXY_KEY")

    build = lambda do
      ENV["MASTER_NO_POOL_PROBES"] = "1"
      router = Master::CLI::Routing::ModelRouter.new(
        config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
      )
      router.instance_variable_get(:@rules)["openai_compatible"] = {}
      ENV.delete("MASTER_NO_POOL_PROBES")
      router
    ensure
      ENV.delete("MASTER_NO_POOL_PROBES")
    end

    keyless = build.call
    assert_equal ["gateway:pool-model"], keyless.hosted_models
    assert keyless.reachable?("gateway:pool-model")
    assert_equal "free", keyless.lane_label("gateway:pool-model")
    assert_nil seen.first.last.find { |line| line.downcase.start_with?("authorization:") }

    ENV["MASTER_LLM_GATEWAY_KEY"] = "gateway-test-key"
    keyed = build.call
    assert_equal ["gateway:pool-model"], keyed.hosted_models
    assert_equal "gateway-test-key", keyed.hosted_endpoint_for("gateway:pool-model")[:key]
    assert_equal "Authorization: Bearer gateway-test-key", seen.last.last.find { |line| line.downcase.start_with?("authorization:") }
    assert_match(/\AGET \/v1\/models HTTP\/1\.1\z/, seen.last.first)
  ensure
    ENV.delete("MASTER_NO_POOL_PROBES")
    thread&.kill
    server&.close
  end

  def test_gateway_refuses_plain_http_to_a_non_loopback_host
    ENV["MASTER_LLM_GATEWAY_URL"] = "http://example.invalid/v1"
    ENV["MASTER_NO_POOL_PROBES"] = "1"
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )
    router.instance_variable_get(:@rules)["openai_compatible"] = {}
    ENV.delete("MASTER_NO_POOL_PROBES")

    assert_empty router.hosted_models
    refute router.hosted_model?("gateway:must-not-appear")
  ensure
    ENV.delete("MASTER_NO_POOL_PROBES")
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

  def test_browser_chat_remains_a_fallback_when_api_keys_are_configured
    ENV["OPENROUTER_API_KEY"] = "sk-or-v1-" + ("a" * 64)
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )

    assert router.web_chat_enabled?
    chain = router.fallback_chain(task_type: :exploration)
    assert_includes chain, "web-chat:grok"
    assert_equal chain, router.send(:priority_fallback_order, chain)
  end

  def test_browser_chat_can_be_disabled_explicitly
    ENV["MASTER_NO_WEB_CHAT"] = "1"
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: Master.free_primary_model), root: Master::ROOT,
    )

    refute router.web_chat_enabled?
    refute_includes router.fallback_chain(task_type: :exploration), "web-chat:grok"
  end

  def test_local_only_mode_excludes_browser_chat
    ENV["MASTER_LOCAL_ONLY"] = "1"
    router = Master::CLI::Routing::ModelRouter.new(
      config: FakeConfig.new(model: "ollama:gemma3:4b"), root: Master::ROOT,
    )

    refute router.web_chat_enabled?
    refute_includes router.fallback_chain(task_type: :exploration), "web-chat:grok"
  end

  def test_undiscovered_hosted_model_is_not_classified_as_keyless_free
    router = Master::CLI::Routing::ModelRouter.allocate
    router.instance_variable_set(:@rules, { "openai_compatible" => {} })
    router.define_singleton_method(:hosted_model?) { |_model| true }
    router.define_singleton_method(:hosted_endpoint_for) { |_model| nil }

    refute router.send(:free_api_model?, "llm7:stale-model")
  end

  def test_browser_chat_follows_free_apis_and_precedes_local_fallbacks
    router = Master::CLI::Routing::ModelRouter.allocate
    router.instance_variable_set(:@rules, { "models" => {} })
    router.instance_variable_set(:@config, FakeConfig.new(model: "configured:model"))
    router.define_singleton_method(:local_only?) { false }
    router.define_singleton_method(:preferred) { |task_type:| "preferred:model" }
    router.define_singleton_method(:tier_ids) { ["vendor/free-api:model:free"] }
    router.define_singleton_method(:primary_models) { ["premium:subscription"] }
    router.define_singleton_method(:agy_catalog_models) { [] }
    router.define_singleton_method(:cli_lane_models) { |wait: false| [] }
    router.define_singleton_method(:continuity_models) { ["openrouter/free-model:free"] }
    router.define_singleton_method(:hosted_models) { ["llm7:free-model"] }
    router.define_singleton_method(:hosted_model?) { |model| model.start_with?("llm7:") }
    router.define_singleton_method(:hosted_endpoint_for) { |_model| { key: nil } }
    router.define_singleton_method(:browser_chat_models) { ["web-chat:grok"] }
    router.define_singleton_method(:local_server_models) { ["local:qwen"] }
    router.define_singleton_method(:replicate_models) { [] }
    router.define_singleton_method(:local_models) { ["ollama:gemma3:4b"] }

    chain = router.send(:priority_fallback_order, router.send(:chain_for, :exploration))
    positions = %w[
      premium:subscription vendor/free-api:model:free openrouter/free-model:free
      llm7:free-model web-chat:grok local:qwen ollama:gemma3:4b
    ].map { |model| chain.index(model) }

    refute_includes positions, nil, "every lane in the fallback policy must be present"
    assert_equal positions.sort, positions, "fallback order must be premium, free API, browser, then local"
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
