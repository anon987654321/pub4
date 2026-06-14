# frozen_string_literal: true

require_relative "test_helper"

class TestLLMDispatcher < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(name, payload = nil, **kwargs)
      @events << [name, payload || kwargs]
    end
  end

  class FakeSession
    attr_accessor :topic, :messages
    attr_reader :costs

    def initialize
      @costs = []
      @messages = []
    end

    def record_cost(amount, model:, tokens:)
      @costs << { amount: amount, model: model, tokens: tokens }
    end
  end

  ReplyWithUsage = Struct.new(:input_tokens, :output_tokens, :cached_tokens, :cache_creation_tokens)
  ReplyWithContent = Struct.new(:content)

  def test_record_usage_publishes_cost_transparency_line
    dispatcher, session, bus = build_dispatcher
    reply = ReplyWithUsage.new(100, 50, 20, 10)

    dispatcher.send(:record_usage, reply, "test-model")

    event = bus.events.find { |name, _payload| name == "llm:cost" }
    assert_equal "test-model", event.last[:model]
    assert_equal 150, event.last[:tokens]
    assert_match(/\A\[\$\d+\.\d{4}, 150 tokens\]\z/, event.last[:line])
    assert_equal event.last[:line], bus.events.find { |name, _| name == "llm:transparency" }.last[:line]
    complete = bus.events.find { |name, _payload| name == "llm:call_complete" }
    assert_equal 100, complete.last[:tokens_in]
    assert_equal 50, complete.last[:tokens_out]
    assert_equal event.last[:cost], complete.last[:cost_usd]
    assert_equal 1, session.costs.size
  end

  def test_record_usage_estimates_cost_when_provider_omits_usage
    dispatcher, _session, bus = build_dispatcher
    reply = ReplyWithContent.new("abcd" * 250)

    dispatcher.send(:record_usage, reply, "fallback-model")

    event = bus.events.find { |name, _payload| name == "llm:cost" }
    assert_equal true, event.last[:estimated]
    assert_equal 250, event.last[:tokens]
    assert_equal "[$0.0038, 250 tokens]", event.last[:line]
    complete = bus.events.find { |name, _payload| name == "llm:call_complete" }
    assert_equal 250, complete.last[:tokens_in]
    assert_equal 0, complete.last[:tokens_out]
  end

  def test_active_file_types_collects_extensions_from_session_context
    dispatcher, session, _bus = build_dispatcher
    session.topic = "editing MASTER/lib/judge/scan/rules/js_rules.rb and config/routes.json"
    session.messages << { content: "also touch DEPLOY/rails/brgen/app/jobs/postpro_job.rb" }

    assert_equal [".json", ".rb"], dispatcher.send(:active_file_types).sort
  end

  def test_tool_availability_respects_file_types_metadata
    dispatcher, session, _bus = build_dispatcher
    session.topic = "editing config/routes.json"

    assert dispatcher.send(:tool_available_for_context?, {})
    assert dispatcher.send(:tool_available_for_context?, { "file_types" => [".json"] })
    refute dispatcher.send(:tool_available_for_context?, { "file_types" => [".rb"] })
  end

  private

  def build_dispatcher
    dispatcher = Master::Judge::LLMDispatcher.allocate
    session = FakeSession.new
    bus = FakeBus.new
    dispatcher.instance_variable_set(:@session, session)
    dispatcher.instance_variable_set(:@bus, bus)
    [dispatcher, session, bus]
  end
end
