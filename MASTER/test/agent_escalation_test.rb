# frozen_string_literal: true

require "minitest/autorun"

class AgentEscalationTest < Minitest::Test
  ResultOk = Struct.new(:value) do
    def ok? = true
    def to_s = value
  end

  ResultErr = Struct.new(:message) do
    def ok? = false
  end

  class FakeDispatcher
    attr_reader :models

    def initialize
      @models = []
    end

    def send_with_cache(model, *_args, **_kwargs)
      @models << model
      ResultOk.new("ok-from-#{model}")
    end

    def claude_cli_model?(_model)
      false
    end

    def tool_capable?(_model)
      false
    end
  end

  class FakeRouter
    def fallback_chain(task_type:)
      ["cheap-model"]
    end

    def classify_intent(_message)
      :general
    end

    def escalate_if_low_confidence(*_args)
      "strong-model"
    end
  end

  def test_escalation_uses_stronger_model
    dispatcher = FakeDispatcher.new

    agent = Master::Agent.allocate
    agent.instance_variable_set(:@dispatcher, dispatcher)
    agent.instance_variable_set(:@model_router, FakeRouter.new)
    agent.instance_variable_set(:@config, Struct.new(:reasoning_mode, :task_type, :model).new("direct", :general, "cheap-model"))
    agent.instance_variable_set(:@session, Struct.new(:messages).new([]))
    agent.instance_variable_set(:@bus, nil)

    def agent.prepare_chat_turn(*) = nil
    def agent.check_rate_limit = nil
    def agent.conversation_context(*) = []
    def agent.apply_reasoning_mode(message, **) = message
    def agent.publish_llm_success(*) = nil
    def agent.attempt_chat_with_fallbacks(candidate_models:, **)
      ResultOk.new(candidate_models.first)
    end

    response = agent.send(:maybe_escalate, ResultOk.new("weak"), "hello", stream: false, escalation_depth: 0)

    assert_equal "strong-model", response.to_s
  end
end
