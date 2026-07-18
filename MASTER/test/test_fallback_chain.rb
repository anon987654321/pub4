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
    agent.define_singleton_method(:filter_prompt) { |msg| msg }
    agent.define_singleton_method(:apply_reasoning_mode) { |msg, **| msg }
    agent
  end

  def test_timeout_skips_retries_and_later_modes_for_same_model
    dispatcher = CountingDispatcher.new(
      "claude-cli:claude-opus-4-8" => -> { Master::Result.err("timed out", category: :timeout) },
      "z-ai/glm-4.5-air:free" => -> { Master::Result.ok("fallback ok") },
      :default => -> { Master::Result.err("unexpected", category: :provider_error) }
    )
    agent = build_agent(dispatcher)
    models = %w[claude-cli:claude-opus-4-8 z-ai/glm-4.5-air:free]

    response = agent.send(
      :attempt_chat_with_fallbacks,
      candidate_models: models,
      prompt: "hi",
      context: [],
      stream: false
    )

    assert_instance_of Master::Result::Ok, response
    assert_equal "fallback ok", response.value!
    assert_equal 2, dispatcher.calls.size
    assert_equal "claude-cli:claude-opus-4-8", dispatcher.calls[0]
    assert_equal "z-ai/glm-4.5-air:free", dispatcher.calls[1]
  end

  def test_failover_skip_model_identifies_transient_errors
    agent = build_agent(CountingDispatcher.new({}))
    timeout = Master::Result.err("timed out", category: :timeout)
    provider = Master::Result.err("upstream", category: :provider_error)

    assert agent.send(:failover_skip_model?, timeout)
    refute agent.send(:failover_skip_model?, provider)
  end
end