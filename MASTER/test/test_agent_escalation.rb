# frozen_string_literal: true

require "minitest/autorun"

class AgentEscalationTest < Minitest::Test
  ResultOk  = Struct.new(:value) { def ok? = true;  def to_s = value }
  ResultErr = Struct.new(:message) { def ok? = false }

  class FakeDispatcher
    attr_reader :models
    def initialize = @models = []
    def send_with_cache(model, *) = ResultOk.new("ok-from-#{model}").tap { @models << model }
    def claude_cli_model?(_) = false
    def tool_capable?(_)     = false
  end

  class FakeRouter
    def fallback_chain(task_type:)       = ["cheap-model"]
    def classify_intent(_)               = :general
    def escalate_if_low_confidence(*) = "strong-model"
  end

  def test_escalation_uses_stronger_model
    agent = Master::Judge::Agent.allocate
    agent.instance_variable_set(:@dispatcher,    FakeDispatcher.new)
    agent.instance_variable_set(:@model_router,  FakeRouter.new)
    agent.instance_variable_set(:@config,
      Struct.new(:reasoning_mode, :task_type, :model).new("direct", :general, "cheap-model"))
    agent.instance_variable_set(:@session, Struct.new(:messages).new([]))
    agent.instance_variable_set(:@bus, nil)

    agent.define_singleton_method(:prepare_chat_turn)        { |*| nil }
    agent.define_singleton_method(:check_rate_limit)         { nil }
    agent.define_singleton_method(:conversation_context)     { [] }
    agent.define_singleton_method(:apply_reasoning_mode)     { |msg, **| msg }
    agent.define_singleton_method(:attempt_chat_with_fallbacks) do |candidate_models:, **|
      ResultOk.new(candidate_models.first)
    end

    response = agent.send(:maybe_escalate, ResultOk.new("weak"), "hello",
                          stream: false, escalation_depth: 0)
    assert_equal "strong-model", response.to_s
  end

  def test_no_infinite_escalation_same_model
    agent = Master::Judge::Agent.allocate
    router = FakeRouter.new
    router.define_singleton_method(:escalate_if_low_confidence) { |*| "cheap-model" }
    agent.instance_variable_set(:@model_router, router)
    agent.instance_variable_set(:@config,
      Struct.new(:reasoning_mode, :task_type, :model).new("direct", :general, "cheap-model"))
    agent.instance_variable_set(:@bus, nil)

    original = ResultOk.new("original")
    response = agent.send(:maybe_escalate, original, "hello", stream: false, escalation_depth: 0)
    assert_equal original, response
  end
end
