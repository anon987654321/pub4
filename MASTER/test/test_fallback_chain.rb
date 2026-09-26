# frozen_string_literal: true

require_relative "test_helper"

class TestFallbackChain < Minitest::Test
  ResultOk = Struct.new(:value) do
    def ok? = true
    def to_s = value.to_s
  end

  class CountingDispatcher
    attr_reader :calls

    def initialize(responses)
      @responses = responses
      @calls = []
    end

    def send_with_cache(model, *)
      @calls << model
      response = @responses[model] || @responses[:default]
      response.call
    end

    def claude_cli_model?(model_id) = model_id.to_s.start_with?("claude-cli:")
    def tool_capable?(_) = false
  end

  class FakeRouter
    def failover_max_retries = 2
    def failover_cooldown_seconds = 300
  end

  def build_agent(dispatcher)
    agent = Master::Review::Agent.allocate
    agent.instance_variable_set(:@dispatcher, dispatcher)
    agent.instance_variable_set(:@model_router, FakeRouter.new)
    agent.instance_variable_set(:@config,
      Struct.new(:reasoning_mode, :task_type, :model).new("direct", :general, "cheap-model"))
    agent.instance_variable_set(:@bus, nil)
    agent.define_singleton_method(:apply_reasoning_mode) { |msg, **| msg }
    agent
  end

  # The chosen model fails and another answers. The fallback is per-turn;
  # it does not become a new sticky model. A dead chain names every model tried.
  def test_the_session_follows_the_model_that_answered_and_a_dead_chain_names_each_model
    dispatcher = CountingDispatcher.new(
      "ollama:llama3.2:3b" => lambda {
        Master::Io::ModelSkipCache.skip!("ollama:llama3.2:3b", reason: "no model", category: :model_missing)
        Master::Result.err("ollama has no model llama3.2:3b", category: :model_missing)
      },
      "google/gemma-4-31b-it:free" => -> { Master::Result.ok("answered") },
      :default => -> { Master::Result.err("overloaded", category: :timeout) },
    )
    agent = build_agent(dispatcher)
    agent.instance_variable_set(:@pinned_model, "ollama:llama3.2:3b")

    agent.send(:attempt_chat_with_fallbacks, candidate_models: %w[ollama:llama3.2:3b google/gemma-4-31b-it:free],
                                             prompt: "hi", context: [], stream: false)
    assert_equal "ollama:llama3.2:3b", agent.instance_variable_get(:@pinned_model)

    dead = agent.send(:attempt_chat_with_fallbacks, candidate_models: %w[a/one:free b/two:free], prompt: "hi", context: [], stream: false)
    assert_match(/\Ano model answered: a\/one:free: overloaded; b\/two:free: overloaded/, dead.message)
  ensure
    Master::Io::ModelSkipCache.clear!
  end

  def test_timeout_skips_retries_and_later_modes_for_same_model
    dispatcher = CountingDispatcher.new(
      "claude-cli:claude-opus-4-8" => -> { Master::Result.err("timed out", category: :timeout) },
      "z-ai/glm-4.5-air:free" => -> { Master::Result.ok("fallback ok") },
      :default => -> { Master::Result.err("unexpected", category: :provider_error) },
    )
    agent = build_agent(dispatcher)
    models = %w[claude-cli:claude-opus-4-8 z-ai/glm-4.5-air:free]

    response = agent.send(
      :attempt_chat_with_fallbacks,
      candidate_models: models,
      prompt: "hi",
      context: [],
      stream: false,
    )

    assert_instance_of Master::Result::Ok, response
    assert_equal "fallback ok", response.value!
    assert_equal 2, dispatcher.calls.size
    assert_equal "claude-cli:claude-opus-4-8", dispatcher.calls[0]
    assert_equal "z-ai/glm-4.5-air:free", dispatcher.calls[1]
  end

  def test_a_permanent_failure_is_not_retried_on_the_same_model
    dispatcher = CountingDispatcher.new(
      "ghost-model" => -> { Master::Result.err("no such model", category: :validation) },
      "z-ai/glm-4.5-air:free" => -> { Master::Result.ok("fallback ok") },
    )
    agent = build_agent(dispatcher)
    agent.define_singleton_method(:backoff_before_retry) { |*| flunk "slept before retrying a refused request" }

    response = agent.send(:attempt_chat_with_fallbacks, candidate_models: %w[ghost-model z-ai/glm-4.5-air:free],
                                                        prompt: "hi", context: [], stream: false)

    assert_equal "fallback ok", response.value!
    assert_equal %w[ghost-model z-ai/glm-4.5-air:free], dispatcher.calls
    assert_equal "z-ai/glm-4.5-air:free", response.model, "the answer names the routed head, not the model that spoke"
  end

  # Offline is just another provider failure. There is no special local-mode
  # promise; the live candidate chain determines what can answer.
  def test_an_offline_head_does_not_invent_a_local_fallback
    offline = -> { Master::Result.err("Failed to open TCP connection: getaddrinfo", category: :offline) }
    dispatcher = CountingDispatcher.new(
      "anthropic/claude-opus-4.1" => offline,
      "google/gemini-2.5-flash" => offline,
      "ollama:llama3.2:3b" => -> { flunk "offline fallback must not invent a local lane" },
    )
    agent = build_agent(dispatcher)
    router = FakeRouter.new
    router.define_singleton_method(:fallback_chain) { |task_type:| %w[anthropic/claude-opus-4.1 google/gemini-2.5-flash] }
    router.define_singleton_method(:local_models) { ["ollama:llama3.2:3b"] }
    agent.instance_variable_set(:@model_router, router)

    response = agent.send(:attempt_chat_with_fallbacks, candidate_models: %w[anthropic/claude-opus-4.1 google/gemini-2.5-flash],
                                                        prompt: "hi", context: [], stream: false)

    assert response.err?
    assert_equal %w[anthropic/claude-opus-4.1 google/gemini-2.5-flash], dispatcher.calls
  end

  def test_failed_turn_rechecks_the_live_router_for_new_models
    dispatcher = CountingDispatcher.new(
      "first-model" => -> { Master::Result.err("offline", category: :offline) },
      "new-model" => -> { Master::Result.ok("answered") },
    )
    agent = build_agent(dispatcher)
    calls = 0
    router = FakeRouter.new
    router.define_singleton_method(:fallback_chain) do |task_type:|
      calls += 1
      calls == 1 ? ["first-model"] : ["first-model", "new-model"]
    end
    agent.instance_variable_set(:@model_router, router)

    response = agent.send(:attempt_chat_with_fallbacks, candidate_models: ["first-model"],
                                                        prompt: "hi", context: [], stream: false)

    assert_equal "answered", response.value!
    assert_equal %w[first-model new-model], dispatcher.calls
    assert_operator calls, :>=, 1
  end

  def test_failover_skip_model_identifies_transient_errors
    agent = build_agent(CountingDispatcher.new({}))
    timeout = Master::Result.err("timed out", category: :timeout)
    provider = Master::Result.err("upstream", category: :provider_error)

    assert agent.send(:failover_skip_model?, timeout)
    refute agent.send(:failover_skip_model?, provider)
  end
end
