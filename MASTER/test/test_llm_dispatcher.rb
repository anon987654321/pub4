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
      @costs << { amount:, model:, tokens: }
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
    session.topic = "editing MASTER/lib/review/scan/rules/js_rules.rb and config/routes.json"
    session.messages << { content: "also touch RAILS/brgen/app/jobs/postpro_job.rb" }

    assert_equal [".json", ".rb"], dispatcher.send(:active_file_types).sort
  end

  def test_tool_availability_respects_file_types_metadata
    dispatcher, session, _bus = build_dispatcher
    session.topic = "editing config/routes.json"

    assert dispatcher.send(:tool_available_for_context?, {})
    assert dispatcher.send(:tool_available_for_context?, { "file_types" => [".json"] })
    refute dispatcher.send(:tool_available_for_context?, { "file_types" => [".rb"] })
  end

  def test_cache_key_differs_by_system_prompt
    dispatcher, = build_dispatcher

    # Regression: Enhance#enhance calls ask_once(msg, system: ENHANCE_SYSTEM)
    # with the raw user message text; the real turn calls chat(msg) with the
    # persona system prompt. Both produce messages.last[:content] == msg, so
    # a cache key built without the system prompt let the real turn's answer
    # get served the Enhance call's cached completion when the message text
    # matched (confirmed live: "tell me a short joke" returned Enhance's
    # <think> reasoning about JSON rewrite rules instead of a joke).
    key_enhance = dispatcher.send(:cache_key_for, "tell me a short joke", [], "some-model", "you are a message clarity editor")
    key_turn    = dispatcher.send(:cache_key_for, "tell me a short joke", [], "some-model", "you are MASTER, a constitutional coding agent")

    refute_equal key_enhance, key_turn, "different system prompts must not collide on the same cache key"
  end

  def test_cache_key_stable_without_system_prompt
    dispatcher, = build_dispatcher

    k1 = dispatcher.send(:cache_key_for, "hello", [], "some-model")
    k2 = dispatcher.send(:cache_key_for, "hello", [], "some-model")

    assert_equal k1, k2, "identical inputs must still produce a deterministic key"
    assert_equal 64, k1.length, "SHA256 hex is 64 chars"
  end

  def test_send_claude_cli_returns_timeout_error
    dispatcher, _session, _bus = build_dispatcher
    def dispatcher.capture3_with_timeout(_timeout_s, *_args, **)
      raise Timeout::Error
    end
    result = dispatcher.send(:send_claude_cli, "claude-sonnet-4-6", [{ role: "user", content: "hi" }], sys: nil)
    assert_instance_of Master::Result::Err, result
    assert_equal :timeout, result.category
    # Asserts that the message reports THE configured timeout, not that the
    # configured timeout is any particular number. Pinning the literal 60 here
    # meant the one test covering this path failed the moment the default was
    # corrected — a test that fails when a value is tuned is testing the value,
    # and the value is not what this test is for. test_claude_cli_timeout_reads_env_override
    # below already covers where the number comes from.
    expected = Master::Review::LLMDispatcher.const_get(:CLAUDE_CLI_TIMEOUT_S)
    assert_match(/timed out after #{expected}s/, result.message)
  end

  def test_claude_cli_timeout_reads_env_override
    dispatcher, _session, _bus = build_dispatcher
    old = ENV["MASTER_CLAUDE_CLI_TIMEOUT"]
    ENV["MASTER_CLAUDE_CLI_TIMEOUT"] = "12"
    assert_equal 12, dispatcher.send(:claude_cli_timeout_s)
  ensure
    old.nil? ? ENV.delete("MASTER_CLAUDE_CLI_TIMEOUT") : ENV["MASTER_CLAUDE_CLI_TIMEOUT"] = old
  end

  private

  def build_dispatcher
    dispatcher = Master::Review::LLMDispatcher.allocate
    session = FakeSession.new
    bus = FakeBus.new
    dispatcher.instance_variable_set(:@session, session)
    dispatcher.instance_variable_set(:@bus, bus)
    [dispatcher, session, bus]
  end

# Every LLM call in the tree passes through send_with_cache. With no provider
# key each caller used to fail slowly somewhere below it — the council spent
# its whole budget discovering this one persona at a time — so the refusal
# belongs at the door, before the breaker, the cache or the request.
def test_no_provider_key_refuses_at_the_door
  dispatcher = Master::Review::LLMDispatcher.allocate
  result = Master.stub(:any_api_key_present?, false) do
    dispatcher.send_with_cache("any-model", [{ role: "user", content: "hi" }])
  end

  assert_predicate result, :err?
  assert_equal :no_api_key, result.category
end
end
