# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "digest"
require "json"
require "socket"

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

    def record_cost(amount, model:, tokens:, approximate: false)
      @costs << { amount:, model:, tokens:, approximate: }
    end
  end

  # RubyLLM 2.1 separates regular input from cache reads and writes.
  Usage = Struct.new(:input, :output, :cache_read, :cache_write)
  UsageWithDetails = Struct.new(
    :input, :output, :cache_read, :cache_write, :cache_write_by_ttl, :server_tool_use, :reported_cost
  )
  CacheWriteCost = Struct.new(:cache_write)
  ReplyWithUsage = Struct.new(:tokens)
  ReplyWithContent = Struct.new(:content)
  ReplyWithCost = Struct.new(:tokens, :cost, :content)

  # A lane that keeps failing — quota out, a hung binary, a local model timing
  # out — must stop being asked rather than walked again for every rule.
  def test_the_door_stops_asking_once_a_lane_stops_answering
    dispatcher, = build_dispatcher
    door = Master::Io::LaneSilence
    door.record(true, "any-model")

    refute door.silent?("any-model"), "silent before anything failed"
    (door::SILENT_AFTER - 1).times { door.record(false, "any-model", reason: "agy: quota reached") }
    refute door.silent?("any-model"), "tripped early"
    assert door.record(false, "any-model", reason: "agy: quota reached"), "the last failure must report the trip"
    assert door.silent?("any-model")

    refused = dispatcher.send_with_cache("any-model:x", [{ role: "user", content: "hi" }])
    assert_predicate refused, :err?
    assert_equal :no_api_key, refused.category
    assert_match(/no any-model answer.*last: agy: quota reached/, refused.message)

    door.record(true, "any-model")
    refute door.silent?("any-model"), "one answer must clear it without a restart"
  ensure
    Master::Io::LaneSilence.record(true, "any-model")
  end

  # One lane's spent quota must not make the shared door refuse another lane
  # that still answers.
  def test_a_spent_lane_does_not_silence_the_others
    door = Master::Io::LaneSilence
    door::SILENT_AFTER.times { door.record(false, "agy", reason: "Individual quota reached") }

    assert door.silent?("agy")
    refute door.silent?("claude-cli"), "agy's quota must not refuse claude-cli"
    assert_equal "claude-cli", door.lane_of("claude-cli:claude-opus-5-5")
  ensure
    door.record(true, "agy")
  end

  # `claude --print` from inside a session can hang and be killed, which is exit
  # 124 and two empty streams; the error must say so rather than "claude-cli:".
  def test_a_cli_that_dies_silently_says_what_it_did
    dispatcher, = build_dispatcher
    killed = Struct.new(:success?, :exitstatus).new(false, 124)
    dispatcher.define_singleton_method(:capture3_with_timeout) { |*_a, **_k| ["", "", killed] }

    result = dispatcher.send(:claude_cli_call, "claude-sonnet-4-6", [{ role: "user", content: "hi" }], nil)

    assert_equal "claude-cli: exited 124 with nothing on either stream", result.message
  end

  def test_preflight_error_event_redacts_raw_exception_text
    dispatcher, _session, bus = build_dispatcher
    private_error = "preflight failed at https://private.example/?token=preflight-secret"
    router = Object.new
    router.define_singleton_method(:unreachable_reason) { |_model, wait: false| raise IOError, private_error }
    dispatcher.instance_variable_set(:@model_router, router)

    result = dispatcher.send(:forced_lane_unavailable, "ollama:qwen3:8b")

    assert_nil result, "the preflight fallback policy remains unchanged"
    _name, payload = bus.events.find { |name, _| name == "llm:preflight_error" }
    assert_equal "ollama:qwen3:8b", payload[:model]
    assert_equal "IOError", payload[:error_class]
    assert_equal Digest::SHA256.hexdigest(private_error), payload[:error_digest]
    assert_equal private_error.bytesize, payload[:error_bytes]
    refute payload.key?(:error)
    refute_includes bus.events.inspect, private_error
  end

  def test_provider_outcome_event_redacts_raw_error_text
    dispatcher, _session, bus = build_dispatcher
    private_error = "auth failed at https://private.example/?token=not-for-logs"

    dispatcher.send(
      :record_provider_outcome, "provider-a", :provider_error, error: private_error
    )

    _name, payload = bus.events.find { |name, _| name == "llm:provider_outcome" }
    assert_equal Digest::SHA256.hexdigest(private_error), payload[:error_digest]
    assert_equal private_error.bytesize, payload[:error_bytes]
    refute payload.key?(:error)
    refute_includes bus.events.inspect, private_error
  end

  def test_record_usage_publishes_cost_transparency_line
    dispatcher, session, bus = build_dispatcher
    reply = ReplyWithUsage.new(Usage.new(100, 50, 20, 10))

    dispatcher.send(:record_usage, reply, "test-model")

    event = bus.events.find { |name, _payload| name == "llm:cost" }
    assert_equal "test-model", event.last[:model]
    assert_equal 180, event.last[:tokens]
    assert_equal 0.002468, event.last[:cost]
    assert_match(/\A\[~\$0\.0025, 180 tokens\]\z/, event.last[:line])
    assert_equal event.last[:line], bus.events.find { |name, _| name == "llm:transparency" }.last[:line]
    complete = bus.events.find { |name, _payload| name == "llm:call_complete" }
    assert_equal 130, complete.last[:tokens_in]
    assert_equal 50, complete.last[:tokens_out]
    assert_equal true, complete.last[:cache_hit]
    assert_equal event.last[:cost], complete.last[:cost_usd]
    assert_equal 1, session.costs.size
  end

  def test_provider_reported_cost_overrides_estimate_and_preserves_reported_zero
    [0.001234, 0.0].each do |reported_cost|
      dispatcher, session, bus = build_dispatcher
      usage = UsageWithDetails.new(100, 50, 20, 10, nil, nil, reported_cost)

      dispatcher.send(:record_usage, ReplyWithUsage.new(usage), "test-model")

      event = bus.events.find { |name, _payload| name == "llm:cost" }
      assert_equal reported_cost, event.last[:cost]
      assert_equal 180, event.last[:tokens]
      refute event.last[:approximate]
      assert_equal reported_cost, session.costs.last[:amount]
    end
  end

  def test_cache_write_lifetime_uses_ruby_llm_priced_component
    dispatcher, session, bus = build_dispatcher
    usage = UsageWithDetails.new(100, 50, 0, 10, { "5m" => 10 }, nil, nil)
    reply = ReplyWithCost.new(usage, CacheWriteCost.new(0.000099), "reply")

    dispatcher.send(:record_usage, reply, "test-model")

    event = bus.events.find { |name, _payload| name == "llm:cost" }
    assert_equal 160, event.last[:tokens]
    assert_equal 0.002349, event.last[:cost]
    assert_equal true, event.last[:approximate], "unknown model pricing remains approximate"
    assert_equal 160, session.costs.last[:tokens]
  end

  def test_record_usage_estimates_cost_when_provider_omits_usage
    dispatcher, _session, bus = build_dispatcher
    reply = ReplyWithContent.new("abcd" * 250)

    dispatcher.send(:record_usage, reply, "fallback-model")

    event = bus.events.find { |name, _payload| name == "llm:cost" }
    assert_equal true, event.last[:estimated]
    assert_equal 250, event.last[:tokens]
    assert_equal "[~$0.0038, 250 tokens]", event.last[:line]
    complete = bus.events.find { |name, _payload| name == "llm:call_complete" }
    assert_equal 250, complete.last[:tokens_in]
    assert_equal 0, complete.last[:tokens_out]
    assert_equal false, complete.last[:cache_hit]
  end

  def test_active_file_types_collects_extensions_from_session_context
    dispatcher, session, _bus = build_dispatcher
    session.topic = "editing MASTER/law/javascript.rb and config/routes.json"
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

    # Enhance#enhance calls ask_once(msg, system: ENHANCE_SYSTEM) with the raw
    # user message; the real turn sends the same text under the persona system
    # prompt. A key built without the system prompt would serve one the other's
    # cached completion.
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
  # :llm_call_failure is not in fallback_policy.on, so these must classify as
  # :budget and :rate_limit to make the chain walk on.
  def test_billing_and_rate_errors_classify_as_failover_categories
    dispatcher, = build_dispatcher

    assert dispatcher.send(:billing_error?, StandardError.new("Insufficient credits. Add more using https://openrouter.ai"))
    assert dispatcher.send(:billing_error?, StandardError.new("402 Payment Required"))
    refute dispatcher.send(:billing_error?, StandardError.new("connection reset"))

    assert dispatcher.send(:rate_limit_error?, StandardError.new("Rate limit exceeded: free-models-per-min"))
    assert dispatcher.send(:rate_limit_error?, StandardError.new("HTTP 429 Too Many Requests"))
    refute dispatcher.send(:rate_limit_error?, StandardError.new("connection reset"))
  end

  # The breaker turns a resolver failure into :provider_error; an unreachable
  # lane (no network, a refused connection, a local daemon that is down) is
  # :offline, and the failover chain decides whether another lane answers.
  def test_a_network_failure_classifies_as_offline
    dispatcher, = build_dispatcher
    dns = Master::Result.err("Failed to open TCP connection to openrouter.ai:443 (getaddrinfo: nodename nor servname provided, or not known)",
                             category: :provider_error)
    refused = Master::Result.err("Failed to open TCP connection to openrouter.ai:443 (Connection refused)", category: :provider_error)
    local = Master::Result.err("ollama unreachable at http://gpu.lan:11434: getaddrinfo failed", category: :provider_error)

    assert_equal :offline, dispatcher.send(:reclassify_provider_error, dns).category
    assert_equal :offline, dispatcher.send(:reclassify_provider_error, refused).category
    assert_equal :offline, dispatcher.send(:reclassify_provider_error, local).category
    assert_equal :offline, dispatcher.send(:classified_call_failure, SocketError.new("Network is unreachable")).category
  end

  def test_ruby_llm_typed_errors_map_to_master_failover_categories
    dispatcher, = build_dispatcher
    cases = [
      [RubyLLM::PaymentRequiredError.new("payment required"), :budget],
      [RubyLLM::RateLimitError.new("provider rejected the request"), :rate_limit],
      [RubyLLM::OverloadedError.new("capacity reached"), :rate_limit],
      [RubyLLM::BadRequestError.new("invalid payload"), :invalid_request],
      [RubyLLM::ContextLengthExceededError.new("context too long"), :invalid_request],
      [RubyLLM::UnsupportedAttachmentError.new("unsupported media"), :invalid_request],
      [RubyLLM::ModelNotFoundError.new("unknown model"), :model_missing],
      [RubyLLM::ServerError.new("upstream failure"), :provider_error],
      [RubyLLM::ServiceUnavailableError.new("temporarily unavailable"), :provider_error],
    ]

    cases.each do |error, expected|
      result = dispatcher.send(:classified_call_failure, error)
      assert_equal expected, result.category, error.class.name
    end
  end

  def test_ruby_llm_auth_errors_distinguish_missing_keys_from_rejected_keys
    dispatcher, = build_dispatcher
    error = RubyLLM::UnauthorizedError.new("credentials rejected")

    with_key = Master.stub(:any_api_key_present?, true) do
      dispatcher.send(:classified_call_failure, error)
    end
    without_key = Master.stub(:any_api_key_present?, false) do
      dispatcher.send(:classified_call_failure, error)
    end

    assert_equal :auth_error, with_key.category
    assert_equal :no_api_key, without_key.category
  end

  def test_invalid_request_uses_a_declared_non_retriable_category
    dispatcher, = build_dispatcher

    result = dispatcher.send(:classified_call_failure, StandardError.new("invalid request: unsupported parameter"))

    assert_equal :invalid_request, result.category
    assert result.permanent?
    refute result.retriable?
  end

  def test_a_crashed_local_runner_is_classified_for_immediate_failover
    dispatcher, = build_dispatcher
    error = Master::Result.err(
      'ollama 500: {"error":"llama-server process has terminated: failed to create library"}',
      category: :provider_error,
    )

    assert_equal :provider_error, dispatcher.send(:reclassify_provider_error, error).category
    assert_equal :offline, dispatcher.send(
      :reclassify_provider_error, error, model: "ollama:gemma3:4b"
    ).category
  end

  def test_timeout_pipe_readers_are_silent_when_the_child_closes_first
    dispatcher, = build_dispatcher

    assert_raises(Timeout::Error) do
      _out, _err = capture_io do
        dispatcher.send(
          :capture3_with_timeout,
          0.05,
          RbConfig.ruby,
          "-e",
          "trap('TERM') { exit! }; sleep 2",
        )
      end
    end
  end

  def test_send_claude_cli_returns_timeout_error
    dispatcher, _session, _bus = build_dispatcher
    def dispatcher.capture3_with_timeout(_timeout_s, *_args, **)
      raise Timeout::Error
    end
    result = dispatcher.send(:send_claude_cli, "claude-sonnet-4-6", [{ role: "user", content: "hi" }], sys: nil)
    assert_instance_of Master::Result::Err, result
    assert_equal :timeout, result.category
    # The message reports the configured timeout, whatever its value;
    # test_claude_cli_timeout_reads_env_override covers where the number comes from.
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
  # key every caller would fail slowly somewhere below it, one persona at a time,
  # so the refusal belongs at the door, before the breaker, the cache or the request.
  def test_no_provider_key_refuses_at_the_door
    dispatcher = Master::Review::LLMDispatcher.allocate
    result = Master.stub(:any_api_key_present?, false) do
      dispatcher.send_with_cache("any-model", [{ role: "user", content: "hi" }])
    end

    assert_predicate result, :err?
    assert_equal :no_api_key, result.category
  end

  def test_local_only_rejects_a_remote_model_before_send
    dispatcher = Master::Review::LLMDispatcher.allocate
    previous = ENV["MASTER_LOCAL_ONLY"]
    ENV["MASTER_LOCAL_ONLY"] = "1"

    result = dispatcher.send(:local_only_refusal, "anthropic/claude-sonnet-4")

    assert_instance_of Master::Result::Err, result
    assert_equal :offline, result.category
  ensure
    ENV["MASTER_LOCAL_ONLY"] = previous
  end

  # Two claude subprocesses at once, process-wide: four-way contention doubles
  # per-call latency and CLI calls die empty-stderr under it.
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

  # With its tools, `claude --print` can commit inside the /fix checkout past
  # every check /fix makes. The lane answers in text only.
  def test_the_claude_cli_lane_runs_without_tools
    dispatcher, = build_dispatcher
    ok_status = Struct.new(:success?).new(true)
    captured_args = nil
    dispatcher.define_singleton_method(:capture3_with_timeout) do |_t, *args, **|
      captured_args = args
      ["pong", "", ok_status]
    end
    dispatcher.send(:claude_cli_call, "claude-opus-5-5", [{ role: "user", content: "ping" }], nil)

    tools = captured_args.index("--tools")
    refute_nil tools, "the lane must pass --tools"
    assert_equal "", captured_args[tools + 1], "and pass it no tool"
    assert_includes captured_args, "--strict-mcp-config"
    settings = captured_args[captured_args.index("--settings") + 1]
    assert JSON.parse(settings)["disableAllHooks"], "the operator's Claude Code hooks must not run on MASTER's calls"
  end

  # A screenshot given to the claude lane must reach the model, or it judges a
  # layout from numbers. Images ride stream-json.
  def test_the_claude_cli_lane_carries_images_as_stream_json_content_blocks
    dispatcher, = build_dispatcher
    ok_status = Struct.new(:success?).new(true)
    captured = nil
    reply = JSON.generate(type: "result", is_error: false, result: "a black square")
    dispatcher.define_singleton_method(:capture3_with_timeout) do |_t, *args, stdin_data: nil, **|
      captured = [args, stdin_data]
      [reply + "\n", "", ok_status]
    end
    Dir.mktmpdir do |dir|
      path = File.join(dir, "shot.png")
      File.binwrite(path, "\x89PNG fake")
      result = dispatcher.send(:claude_cli_call, "claude-sonnet-5-5", [{ role: "user", content: "look" }], nil,
                               { path:, extra: [{ path: }] })

      assert_equal "a black square", result.value!
    end
    args, stdin = captured
    assert_includes args, "stream-json"
    content = JSON.parse(stdin).dig("message", "content")
    assert_equal %w[image image text], content.map { |block| block["type"] }
    assert_equal "image/png", content.first.dig("source", "media_type")
    assert_includes args, "--strict-mcp-config"
  end

  # `claude` prefers ANTHROPIC_API_KEY to its subscription login. MASTER loads that key for
  # its API lanes, so the keyless CLI lane has to start without it or it fails on a spent key.
  def test_the_claude_cli_lane_starts_without_api_keys_so_the_login_answers
    dispatcher, = build_dispatcher
    ok_status = Struct.new(:success?).new(true)
    captured_env = nil
    dispatcher.define_singleton_method(:capture3_with_timeout) do |_t, *_args, env: {}, **|
      captured_env = env
      ["pong", "", ok_status]
    end
    dispatcher.send(:claude_cli_call, "claude-opus-5-5", [{ role: "user", content: "ping" }], nil)

    %w[ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDECODE CLAUDE_CODE_ENTRYPOINT].each do |name|
      assert captured_env.key?(name) && captured_env[name].nil?, "#{name} must be unset for the lane"
    end
    refute captured_env.key?("CLAUDE_CODE_OAUTH_TOKEN"), "the OAuth token can carry the login"
  end

  # Exit 0 with the limit on stdout is a quota, not the model's answer.
  def test_a_subscription_limit_is_a_quota_not_an_answer
    dispatcher, = build_dispatcher
    ok_status = Struct.new(:success?).new(true)
    dispatcher.define_singleton_method(:capture3_with_timeout) do |*_a, **_k|
      ["You've hit your session limit · resets 4:30pm (Europe/Oslo)\n", "", ok_status]
    end
    result = dispatcher.send(:claude_cli_call, "claude-opus-5-5", [{ role: "user", content: "fix" }], nil)

    assert result.err?
    assert_equal :exhausted, result.category
    assert_equal :quota_exceeded, dispatcher.send(:failure_status, result)
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
    def after_message(&block) = @on_end = block
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

  # Claude CLI explicitly disables native tools and MCP. The dispatcher must
  # keep the authenticated CLI transport while MASTER drives its own guarded
  # ReAct loop; sending this lane through RubyLLM loses the subscription.
  def test_claude_cli_uses_the_guarded_react_tool_loop
    dispatcher, = build_dispatcher
    dispatcher.instance_variable_set(:@tools, [Object.new])
    replies = [
      '<tool_call>{"name":"Browser","args":{"action":"status"}}</tool_call>',
      "The browser returned page evidence.",
    ]
    turns = []
    tool_calls = []

    dispatcher.define_singleton_method(:build_react_system) do |base|
      "#{base}\nAvailable tools: Browser"
    end
    dispatcher.define_singleton_method(:send_claude_cli) do |model_alias, messages, sys:, image: nil|
      turns << { model_alias:, messages: messages.map(&:dup), system: sys }
      Master::Result.ok(replies.shift)
    end
    dispatcher.define_singleton_method(:execute_react_tool) do |name, args|
      tool_calls << { name:, args: }
      "<tool_result name=\"#{name}\">browser ready</tool_result>"
    end

    result = dispatcher.send(
      :send_llm_request,
      "claude-cli:claude-sonnet-5-5",
      [{ role: "user", content: "Read the public news page." }],
      system: "Base instructions",
      stream: false,
    )

    assert_predicate result, :ok?
    assert_equal "The browser returned page evidence.", result.value!
    assert_equal 2, turns.length
    assert_equal "claude-sonnet-5-5", turns.first[:model_alias]
    assert_includes turns.first[:system], "Available tools: Browser"
    assert_includes turns.last[:messages].last[:content], "<tool_result name=\"Browser\">"
    assert_equal "Browser", tool_calls.first[:name]
    assert_equal "status", tool_calls.first[:args]["action"]
  end

  def test_react_tool_metadata_uses_ruby_llm_declared_parameters
    dispatcher, = build_dispatcher

    signature = dispatcher.send(:param_signature, Master::Io::BrowserAgent.allocate)
    assert_equal "(action*, session, url, operation, selector, value, wait, links, max_pages)", signature

    wrapper = Master::Io::LLM::SearchKnowledge.new(Object.new)
    assert_equal({ query: "NRK" }, dispatcher.send(:heal_args, wrapper, { q: "NRK" }))
  end

  def test_react_wrappers_receive_keyword_arguments
    dispatcher, = build_dispatcher
    observed = {}
    cases = {
      Master::Io::WebFetch => { url: "https://nrk.no" },
      Master::Io::WebBrowse => { url: "https://nrk.no" },
      Master::Io::Shell => { command: "printf ok" },
    }

    cases.each do |tool_class, args|
      tool = tool_class.allocate
      tool.define_singleton_method(:call) do |**received|
        observed[tool_class] = received
        Master::Result.ok("called")
      end

      assert_equal "called", dispatcher.send(:invoke_react_tool, tool, args)
    end

    assert_equal "https://nrk.no", observed.fetch(Master::Io::WebFetch).fetch(:url)
    assert_equal "https://nrk.no", observed.fetch(Master::Io::WebBrowse).fetch(:url)
    assert_equal "printf ok", observed.fetch(Master::Io::Shell).fetch(:command)
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

  # The flat rate is a ceiling for a model the registry cannot price, and a
  # row billed at it says so; a priced model's row does not.
  def test_a_flat_rate_charge_is_marked_approximate_and_a_priced_one_is_not
    priced = Struct.new(:input, :output) { def price(direction) = public_send(direction) }.new(3.0, 15.0)
    unpriced, unpriced_session, unpriced_bus = build_dispatcher
    Master::Review::LLMDispatcher.stub(:model_info, nil) do
      unpriced.send(:record_usage, ReplyWithUsage.new(Usage.new(100, 50, 0, 0)), "vendor/unlisted-model")
    end
    billed, billed_session, billed_bus = build_dispatcher
    Master::Review::LLMDispatcher.stub(:model_info, priced) do
      billed.send(:record_usage, ReplyWithUsage.new(Usage.new(100, 50, 0, 0)), "anthropic/claude-sonnet")
    end

    assert unpriced_session.costs.last[:approximate]
    assert unpriced_bus.events.find { |name, _| name == "llm:cost" }.last[:approximate]
    refute billed_session.costs.last[:approximate]
    assert_match(/\A\[\$0\.00\d\d, 150 tokens\]\z/, billed_bus.events.find { |name, _| name == "llm:cost" }.last[:line])
  end

  # MASTER_MODEL rewrites the model at the door, so the answer carries the
  # model that was asked, not the one the caller named.
  def test_an_answer_names_the_model_the_door_actually_asked
    dispatcher, asked = recording_dispatcher
    saved = ENV["MASTER_MODEL"]
    ENV["MASTER_MODEL"] = "claude-cli:claude-opus-4-8"
    result = Master.stub(:any_api_key_present?, true) do
      dispatcher.send_with_cache("routed-model", [{ role: "user", content: "hi" }])
    end

    assert_equal "hi", result.value!
    assert_equal ["claude-cli:claude-opus-4-8"], asked
    assert_equal "claude-cli:claude-opus-4-8", result.model
  ensure
    ENV["MASTER_MODEL"] = saved
  end

  # A pin is asked even when its lane is parked; only MASTER_MODEL_STRICT=0 lets it yield to the router.
  def test_a_pin_is_asked_even_when_its_lane_is_parked_unless_failover_is_asked_for
    dispatcher, asked = recording_dispatcher
    saved = %w[MASTER_MODEL MASTER_MODEL_STRICT].to_h { |key| [key, ENV.fetch(key, nil)] }
    ENV["MASTER_MODEL"] = "claude-cli:claude-opus-4-8"
    ask = -> { dispatcher.send_with_cache("routed-model", [{ role: "user", content: "hi" }]) }

    Master.stub(:any_api_key_present?, true) do
      Master::Io::LaneState.stub(:usable?, false) do
        ask.call
        ENV["MASTER_MODEL_STRICT"] = "0"
        ask.call
      end
    end

    assert_equal ["claude-cli:claude-opus-4-8", "routed-model"], asked
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

  # A dispatcher whose network is a list of the models it was asked for.
  def recording_dispatcher
    dispatcher, = build_dispatcher
    asked = []
    breaker = Object.new
    breaker.define_singleton_method(:call) { |_cost, &blk| blk.call }
    cache = Object.new
    cache.define_singleton_method(:fetch) { |_key, _model, &blk| blk.call }

    dispatcher.instance_variable_set(:@cache, cache)
    dispatcher.define_singleton_method(:breaker_for) { |_model| breaker }
    dispatcher.define_singleton_method(:record_provider_result) { |**| nil }
    dispatcher.define_singleton_method(:send_llm_request) { |model, *, **| (asked << model) && Master::Result.ok("hi") }
    [dispatcher, asked]
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
      dispatcher.stub(:build_final_system, []) do
        dispatcher.send(:build_chat_session, openrouter_model, [{ role: "user", content: "hi" }], sys: nil, image: nil)
      end
    end
    RubyLLM.config.openrouter_api_key = "key-after"

    assert_equal "key-before", chat.instance_variable_get(:@config).openrouter_api_key
  ensure
    RubyLLM.config.openrouter_api_key = saved
  end

  # A Claude lane splits the persona prompt so its static half is cached. The
  # split reads the persona from the proc, so it applies only when the prompt it
  # was handed is that persona; anything else, such as a swarm reviewer's JSON
  # verdict contract, goes to the model as given.
  def test_a_claude_lane_sends_the_system_prompt_it_was_handed
    dispatcher, = build_dispatcher
    dispatcher.instance_variable_set(:@system_prompt_proc, -> { { static: "PERSONA", dynamic: "TURN" } })

    role = dispatcher.send(:build_final_system, "anthropic/claude-sonnet-4", "LAW\n\nanswer in JSON")
    persona = dispatcher.send(:build_final_system, "anthropic/claude-sonnet-4", "PERSONA\n\nTURN")

    assert_equal ["LAW\n\nanswer in JSON"], role.map { |block| block[:text] }
    assert_equal %w[PERSONA TURN], persona.map { |block| block[:text] }
  end

  # A CLI lane without its binary must refuse permanently: a retriable ENOENT
  # would make a chain sleep through backoff on it once per file of a scan.
  def test_a_cli_lane_without_its_binary_refuses_permanently
    dispatcher, = build_dispatcher
    previous = ENV["MASTER_NO_CLAUDE_CLI"]
    ENV["MASTER_NO_CLAUDE_CLI"] = "1"
    result = dispatcher.send(:send_claude_cli, "claude-sonnet-4-6", [{ role: "user", content: "hei" }], sys: nil)

    assert_predicate result, :err?
    assert_predicate result, :permanent?
    assert_includes result.message, "no claude on PATH"
  ensure
    ENV["MASTER_NO_CLAUDE_CLI"] = previous
  end

  # A reasoning model sends its working beside its answer; appended, every
  # reader would have to strip it.
  def test_a_reasoning_replys_working_stays_out_of_its_answer
    dispatcher, = build_dispatcher
    thinking = Struct.new(:text).new("the user asked who I am, so I introduce myself")
    reply = Struct.new(:content, :thinking).new("Hei! Jeg er MASTER.", thinking)

    assert_equal "Hei! Jeg er MASTER.", dispatcher.send(:extract_response, reply)
  end

  # With nothing else to say, the working is the only answer there is.
  def test_a_reply_that_is_only_working_answers_with_it
    dispatcher, = build_dispatcher
    thinking = Struct.new(:text).new("still deciding")
    reply = Struct.new(:content, :thinking).new("", thinking)

    assert_equal "still deciding", dispatcher.send(:extract_response, reply)
  end

  # A schema-bound reply arrives parsed, and Hash#to_s is Ruby's inspect, which
  # the fold's parser cannot read as a JSON object.
  def test_a_parsed_schema_reply_goes_back_out_as_json
    dispatcher, = build_dispatcher
    reply = Struct.new(:content).new({ "verb" => "note", "why" => "look first", "args" => {} })

    text = dispatcher.send(:extract_response, reply)

    assert_equal "note", JSON.parse(text)["verb"]
  end

  # codex takes its prompt on stdin and writes the answer to a file; a lane
  # whose model is auto passes no model flag, so the CLI keeps its own default.
  def test_a_cli_lane_asks_on_stdin_and_reads_the_reply_file
    dispatcher, = build_dispatcher
    seen = {}
    dispatcher.define_singleton_method(:capture3_with_timeout) do |_t, *args, stdin_data: nil|
      seen[:args], seen[:stdin] = args, stdin_data
      File.write(args[args.index("--output-last-message") + 1], "pong\n")
      ["progress chatter", "", Struct.new(:success?).new(true)]
    end

    result = dispatcher.send(:send_cli_lane, "codex-cli:auto", [{ role: "user", content: "ping" }], sys: "LAW")

    assert_equal "pong", result.value!
    assert seen[:stdin].start_with?("LAW\n\n---\n\n")
    assert_includes seen[:stdin], "ping"
    refute_includes seen[:args], "--model"
  end

  # A spent plan is a spent balance to the chain: it walks on rather than
  # retrying codex until tomorrow.
  def test_a_spent_cli_plan_reads_as_budget
    dispatcher, = build_dispatcher
    failed = Struct.new(:success?, :exitstatus).new(false, 1)
    dispatcher.define_singleton_method(:capture3_with_timeout) do |*_a, **_k|
      ["", "ERROR: You've hit your usage limit. Upgrade to Plus to continue using Codex", failed]
    end

    result = dispatcher.send(:send_cli_lane, "codex-cli:auto", [{ role: "user", content: "ping" }], sys: nil)

    assert_equal :budget, dispatcher.send(:reclassify_provider_error, result).category
    assert_match(/usage limit/, result.message)
    assert dispatcher.send(:rate_limit_error?, StandardError.new("Upstream error from Nvidia: Service temporarily overloaded"))
  end

  def test_a_local_server_answers_through_the_openai_chat_call
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      socket = server.accept
      length = 0
      while (line = socket.gets.to_s.strip) != ""
        length = line.split(":").last.to_i if line.downcase.start_with?("content-length")
      end
      request = JSON.parse(socket.read(length))
      body = JSON.generate("choices" => [{ "message" => { "content" => "hello from #{request['model']}" } }])
      socket.print("HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      socket.close
    end
    dispatcher, = build_dispatcher
    base = "http://127.0.0.1:#{server.addr[1]}/v1"
    router = Object.new
    router.define_singleton_method(:local_server_for) { |_id| base }
    dispatcher.instance_variable_set(:@model_router, router)

    result = dispatcher.send(:send_local_server, "local:Qwen/Qwen3-4B", [{ role: "user", content: "hi" }], sys: nil)

    assert_equal "hello from Qwen/Qwen3-4B", result.value!
  ensure
    thread&.kill
    server&.close
  end

  # A hosted endpoint is asked for the model without its lane prefix, with its
  # key as a Bearer token; a keyless endpoint sends no Authorization at all.
  def test_a_hosted_endpoint_answers_with_its_key_and_the_bare_model_name
    seen = {}
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      socket = server.accept
      length = 0
      while (line = socket.gets.to_s.strip) != ""
        length = line.split(":").last.to_i if line.downcase.start_with?("content-length")
        seen[:auth] = line if line.downcase.start_with?("authorization")
      end
      request = JSON.parse(socket.read(length))
      body = JSON.generate("choices" => [{ "message" => { "content" => "hello from #{request['model']}" } }])
      socket.print("HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      socket.close
    end
    dispatcher, = build_dispatcher
    endpoint = { base: "http://127.0.0.1:#{server.addr[1]}/v1", key: "sk-free", max_concurrency: 1, quota_bucket: "dispatcher-hosted-test" }
    router = Object.new
    router.define_singleton_method(:hosted_endpoint_for) { |id| endpoint if id.start_with?("freehost:") }
    dispatcher.instance_variable_set(:@model_router, router)

    assert dispatcher.send(:hosted_lane?, "freehost:GLM-5.3-Flash")
    refute dispatcher.send(:hosted_lane?, "gpt-4o")
    result = dispatcher.send(:send_hosted, "freehost:GLM-5.3-Flash", [{ role: "user", content: "hi" }], sys: nil)

    assert_equal "hello from GLM-5.3-Flash", result.value!
    assert_equal "Authorization: Bearer sk-free", seen[:auth]
  ensure
    thread&.kill
    server&.close
  end

  def test_an_http_lane_names_auth_budget_and_rate_limit_categories
    dispatcher, = build_dispatcher
    response_class = Struct.new(:code, :body, :fields) do
      def get_fields(name)
        fields[name]
      end
    end
    response = ->(code, fields = {}) { response_class.new(code, "no", fields) }

    assert_equal :no_api_key, dispatcher.send(:http_lane_error, "replicate", response.call("401")).category
    assert_equal :budget, dispatcher.send(:http_lane_error, "replicate", response.call("402")).category
    assert_equal :provider_error, dispatcher.send(:http_lane_error, "replicate", response.call("503")).category

    limited = dispatcher.send(:http_lane_error, "freehost", response.call("429", "Retry-After" => ["30"]))
    assert_equal :rate_limit, limited.category
    assert_match(/Retry-After: 30/, limited.message)
  end

  private

  def build_dispatcher
    dispatcher = Master::Review::LLMDispatcher.allocate
    session = FakeSession.new
    bus = FakeBus.new
    dispatcher.instance_variable_set(:@session, session)
    dispatcher.instance_variable_set(:@bus, bus)
    dispatcher.instance_variable_set(:@availability, Master::CLI::Routing::AvailabilityPolicy.new(config: {}))
    [dispatcher, session, bus]
  end
end
