# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

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

  # A billing or rate-limit refusal cannot succeed on an in-place retry, and
  # :llm_call_failure is not in fallback_policy.on — seven rule passes died
  # on "Insufficient credits" with claude-cli unused in the same chain
  # (2026-08-19). :budget and :rate_limit make the chain walk on.
  def test_billing_and_rate_errors_classify_as_failover_categories
    dispatcher, = build_dispatcher

    assert dispatcher.send(:billing_error?, StandardError.new("Insufficient credits. Add more using https://openrouter.ai"))
    assert dispatcher.send(:billing_error?, StandardError.new("402 Payment Required"))
    refute dispatcher.send(:billing_error?, StandardError.new("connection reset"))

    assert dispatcher.send(:rate_limit_error?, StandardError.new("Rate limit exceeded: free-models-per-min"))
    assert dispatcher.send(:rate_limit_error?, StandardError.new("HTTP 429 Too Many Requests"))
    refute dispatcher.send(:rate_limit_error?, StandardError.new("connection reset"))
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

  # Two claude subprocesses at once, process-wide: the dispatcher's latency
  # table measured four-way contention doubling per-call latency, and the
  # 2026-08-20 proof run showed CLI calls dying empty-stderr under it.
  def test_claude_cli_concurrency_is_capped_at_two
    dispatcher, = build_dispatcher
    require "monitor"
    lock = Monitor.new
    state = { live: 0, max: 0 }
    ok_status = Struct.new(:success?).new(true)
    probe = lambda do
      lock.synchronize { state[:live] += 1; state[:max] = [state[:max], state[:live]].max }
      sleep 0.05
      lock.synchronize { state[:live] -= 1 }
      ["ok", "", ok_status]
    end
    dispatcher.define_singleton_method(:capture3_with_timeout) { |_t, *_a, **_k| probe.call }

    threads = 4.times.map do
      Thread.new { dispatcher.send(:send_claude_cli, "claude-sonnet-4-6", [{ role: "user", content: "hi" }], sys: nil) }
    end
    threads.each(&:join)

    assert_operator state[:max], :<=, 2, "expected at most 2 concurrent CLI calls, saw #{state[:max]}"
    assert_operator state[:max], :>=, 2, "stub never overlapped — the probe is not measuring concurrency"
  end

  def test_agy_model_predicate
    dispatcher, = build_dispatcher
    assert dispatcher.agy_model?("agy:auto")
    assert dispatcher.agy_model?("agy:gemini-2.5-pro")
    assert dispatcher.agy_model?("agy")
    refute dispatcher.agy_model?("claude-cli:claude-opus-4-8")
    refute dispatcher.agy_model?("openai/gpt-4o")
  end

  def test_send_agy_cli_returns_timeout_error
    dispatcher, = build_dispatcher
    def dispatcher.capture3_with_timeout(_timeout_s, *_args, **)
      raise Timeout::Error
    end
    result = dispatcher.send(:send_agy_cli, "auto", [{ role: "user", content: "hi" }], sys: nil)
    assert_instance_of Master::Result::Err, result
    assert_equal :timeout, result.category
    expected = Master::Review::LLMDispatcher.const_get(:AGY_CLI_TIMEOUT_S)
    assert_match(/timed out after #{expected}s/, result.message)
  end

  def test_send_agy_cli_success
    dispatcher, = build_dispatcher
    ok_status = Struct.new(:success?).new(true)
    captured_args = nil
    dispatcher.define_singleton_method(:capture3_with_timeout) do |_t, *args, **|
      captured_args = args
      ["AGY OUTPUT", "", ok_status]
    end
    result = dispatcher.send(:send_agy_cli, "gemini-2.5-pro", [{ role: "user", content: "hello" }], sys: "be helpful")
    assert_instance_of Master::Result::Ok, result
    assert_equal "AGY OUTPUT", result.value!
    assert_includes captured_args, "-p"
    assert_includes captured_args, "--model"
    assert_includes captured_args, "gemini-2.5-pro"
  end

  def test_agy_cli_timeout_reads_env_override
    dispatcher, = build_dispatcher
    old = ENV["MASTER_AGY_CLI_TIMEOUT"]
    ENV["MASTER_AGY_CLI_TIMEOUT"] = "15"
    assert_equal 15, dispatcher.send(:agy_cli_timeout_s)
  ensure
    old.nil? ? ENV.delete("MASTER_AGY_CLI_TIMEOUT") : ENV["MASTER_AGY_CLI_TIMEOUT"] = old
  end

  # The gem answers each tool call by asking again with no limit of its own.
  class FakeChat
    def on_end_message(&block) = @on_end = block
    def end_message(message) = @on_end.call(message)
  end

  ToolCallMessage = Struct.new(:tool_call?)

  def test_native_tool_calling_stops_after_react_max_steps_rounds
    dispatcher, = build_dispatcher
    chat = FakeChat.new
    dispatcher.send(:cap_tool_rounds, chat)
    limit = Master::Review::LLMDispatcher::REACT_MAX_STEPS

    limit.times { chat.end_message(ToolCallMessage.new(true)) }
    chat.end_message(ToolCallMessage.new(false))
    assert_raises(Master::Review::LLMDispatcher::RubyLLMSender::ToolRoundLimit) do
      chat.end_message(ToolCallMessage.new(true))
    end
  end

  # A :free id is absent from the registry, so it is zero only where the
  # provider catalog row itself says zero both ways.
  def test_a_free_model_costs_nothing_only_when_the_catalog_says_so
    dispatcher, = build_dispatcher
    flat = Master::Review::LLMDispatcher::COST_PER_TOKEN
    require "io/catalog_index"

    Master::Io::CatalogIndex.stub(:verified_free?, true) do
      assert_equal 0.0, dispatcher.send(:price_per_token, "vendor/unlisted-model:free", :output)
      assert_equal flat, dispatcher.send(:price_per_token, "vendor/unlisted-model", :output), "zero off the suffix alone"
    end
    Master::Io::CatalogIndex.stub(:verified_free?, false) do
      assert_equal flat, dispatcher.send(:price_per_token, "vendor/unlisted-model:free", :output)
    end
  end

  def test_the_catalog_verifies_zero_from_the_providers_row_not_the_price_column
    require "io/catalog_index"
    Dir.mktmpdir do |dir|
      db = File.join(dir, "catalog.sqlite3")
      rows = [
        { id: "a/zero:free", price_prompt: 0.0, price_completion: 0.0, raw: { "pricing" => { "prompt" => "0", "completion" => "0" } } },
        { id: "b/unpriced:free", price_prompt: 0.0, price_completion: 0.0, raw: { "id" => "b/unpriced:free" } },
        { id: "c/paid:free", price_prompt: 0.000001, price_completion: 0.0, raw: { "pricing" => { "prompt" => "0.000001", "completion" => "0" } } },
      ]
      Master::Io::CatalogIndex.new(db_path: db).send(:replace_models, "openrouter", rows)

      assert Master::Io::CatalogIndex.verified_free?("a/zero:free", db_path: db)
      refute Master::Io::CatalogIndex.verified_free?("b/unpriced:free", db_path: db), "a missing price read as free"
      refute Master::Io::CatalogIndex.verified_free?("c/paid:free", db_path: db)
      refute Master::Io::CatalogIndex.verified_free?("a/zero:free", db_path: File.join(dir, "absent.sqlite3"))
      refute File.exist?(File.join(dir, "absent.sqlite3")), "a cost lookup created the catalog"
    end
  end

  # KeyRotator swaps the global key while rule groups run in threads; a chat
  # built before the swap keeps sending the key it started with.
  def test_a_chat_keeps_its_key_when_the_global_key_rotates
    dispatcher, = build_dispatcher
    saved = RubyLLM.config.openrouter_api_key
    openrouter_model = RubyLLM.models.all.find { |model| model.provider == "openrouter" }.id
    RubyLLM.config.openrouter_api_key = "key-before"
    chat = dispatcher.stub(:llm_tools, []) do
      dispatcher.stub(:build_final_system, nil) do
        dispatcher.send(:build_chat_session, openrouter_model,[{ role: "user", content: "hi" }], sys: nil, image: nil)
      end
    end
    RubyLLM.config.openrouter_api_key = "key-after"

    assert_equal "key-before", chat.instance_variable_get(:@config).openrouter_api_key
  ensure
    RubyLLM.config.openrouter_api_key = saved
  end

  # A Claude lane splits the persona prompt so its static half is cached. The
  # split read the persona from the proc and ignored the prompt it was handed,
  # so a caller's own system prompt — a swarm reviewer's JSON verdict contract —
  # never reached a Claude model.
  def test_a_claude_lane_sends_the_system_prompt_it_was_handed
    dispatcher, = build_dispatcher
    dispatcher.instance_variable_set(:@system_prompt_proc, -> { { static: "PERSONA", dynamic: "TURN" } })

    role = dispatcher.send(:build_final_system, "anthropic/claude-sonnet-4", "LAW\n\nanswer in JSON")
    persona = dispatcher.send(:build_final_system, "anthropic/claude-sonnet-4", "PERSONA\n\nTURN")

    assert_equal ["LAW\n\nanswer in JSON"], role.value.map { |block| block[:text] }
    assert_equal %w[PERSONA TURN], persona.value.map { |block| block[:text] }
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

end
