# frozen_string_literal: true

require_relative "test_helper"

# Minimal unit tests for Master::Review::Agent — specifically targeting the Tier-1
# bugs the patch corrects. Does not hit any real LLM.
class TestAgent < Minitest::Test
  include Master

  # Fake collaborators — just enough to construct an Agent.
  FakeConfig  = Struct.new(:model, :task_type, :reasoning_mode) do
    def [](key) = respond_to?(key) ? public_send(key) : nil
  end
  FakeSession = Struct.new(:messages) { def add_message(**) = messages << _1 }
  FakeCB      = Struct.new(:out) { def check_rate!; end; def call(_, &b); b.call; end }
  FakeCache   = Struct.new(:store) { def fetch(k, _m, &b); (store[k] ||= b.call); end }

  # ModelSkipCache is process-wide: a model one test parks stays parked for
  # the next, so each test starts with nothing skipped.
  def setup
    Master::Io::ModelSkipCache.clear!

    @agent = Master::Review::Agent.new(deps: Master::Review::Agent::Dependencies.from_kwargs(
      config:          FakeConfig.new("claude-sonnet-4-6", :exploration, "none"),
      session:         FakeSession.new([]),
      tools:           [],
      circuit_breaker: FakeCB.new,
      cache:           FakeCache.new({}),
    ))
  end

  # tool_capable? — previously a substring-include check. After patch,
  # anchored regex rejects garbage-tailed model ids but accepts real ones.
  # cache_key_for — must produce bounded, deterministic SHA256 keys.
  # escalation flag — must be per-thread, not per-instance.
  def test_chat_turn_stages_a_preference_candidate_only_after_repeated_opted_in_corrections
    require "tmpdir"
    root = Dir.mktmpdir("agent-preference-feedback")
    subject = "agent-owner"
    previous_subject = Fiber[:master_pair_subject]
    previous_visitor = Fiber[:master_visitor]
    Fiber[:master_pair_subject] = subject
    Fiber[:master_visitor] = nil

    permissions = Master::Ground::PersonalPermissions.new(root:)
    permissions.grant(
      scope: "personal_memory", subject:, confirmed_by: "local owner",
      purpose: Master::Ground::PersonalWorkspace::MEMORY_PERMISSION_PURPOSE,
    )
    preferences = Master::Device::OwnerPreferences
    preferences.set_learning(root:, subject:, enabled: true)

    @agent.instance_variable_set(:@config, { "root" => root })
    @agent.instance_variable_set(:@tools, [])
    @agent.instance_variable_set(:@memory, nil)
    messages = []
    session = Object.new
    session.define_singleton_method(:add_message) { |role:, content:| messages << { role:, content: } }
    session.define_singleton_method(:messages) { messages }
    @agent.instance_variable_set(:@session, session)

    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |event, **payload| events << [event, payload] }
    @agent.instance_variable_set(:@bus, bus)

    @agent.send(:prepare_chat_turn, "Your answer is too verbose.")
    assert_empty preferences.status(root:, subject:).fetch("suggestions")

    @agent.send(:prepare_chat_turn, "That answer was too verbose again.")
    candidates = preferences.status(root:, subject:).fetch("suggestions")
    assert_equal 1, candidates.size
    assert_equal "observed_correction", candidates.first.fetch("origin")
    assert events.any? { |event, payload| event == "preferences:suggestion_staged" && payload[:suggestion_id] == candidates.first.fetch("id") }
    refute_includes File.read(preferences.path(root:, subject:)), "Your answer is too verbose"
  ensure
    FileUtils.rm_rf(root) if root
    Fiber[:master_pair_subject] = previous_subject
    Fiber[:master_visitor] = previous_visitor
  end

  def test_unknown_factual_turn_gets_evidence_preflight
    agent = @agent
    knowledge = Object.new
    knowledge.define_singleton_method(:call) { |query:| Master::Result.ok("(no results)") }
    web = Object.new
    web.define_singleton_method(:call) { |query:| Master::Result.ok("fresh evidence for #{query}") }
    agent.instance_variable_set(:@tools, [knowledge, web])
    knowledge.define_singleton_method(:class) { Class.new { def self.name = "Master::Io::SearchKnowledge" } }
    web.define_singleton_method(:class) { Class.new { def self.name = "Master::Io::WebSearch" } }

    agent.send(:prepare_evidence, "How does this obscure protocol work?")

    assert_equal :unknown, Fiber[:master_evidence_mode]
    assert_match(/fresh evidence/, Fiber[:master_evidence_note])
  ensure
    Fiber[:master_evidence_mode] = nil
    Fiber[:master_evidence_note] = nil
  end

def evidence_tools(answer)
  queries = []
  knowledge = Object.new
  knowledge.define_singleton_method(:call) { |query:| Master::Result.ok("(no results)") }
  knowledge.define_singleton_method(:class) { Class.new { def self.name = "Master::Io::SearchKnowledge" } }
  web = Object.new
  web.define_singleton_method(:call) do |query:|
    queries << query
    answer
  end
  web.define_singleton_method(:class) { Class.new { def self.name = "Master::Io::WebSearch" } }
  @agent.instance_variable_set(:@tools, [knowledge, web])
  queries
end

# "does god exist? give me your actual view" ran two web searches on 2026-10-23.
def test_a_request_for_a_view_searches_nothing
  queries = evidence_tools(Master::Result.ok("a page"))

  @agent.send(:prepare_evidence, "does god exist? give me your actual view")

  assert_equal :opinion, Fiber[:master_evidence_mode]
  assert_empty queries
  assert_match(/do not search/, Fiber[:master_evidence_note])
ensure
  Fiber[:master_evidence_mode] = nil
  Fiber[:master_evidence_note] = nil
end

def test_a_current_question_whose_lookup_returns_nothing_says_so
  evidence_tools(Master::Result.err("search unavailable", category: :infrastructure))

  @agent.send(:prepare_evidence, "what is the weather in Bergen tomorrow")

  assert_equal :web_current, Fiber[:master_evidence_mode]
  assert_match(/Web lookup returned nothing/, Fiber[:master_evidence_note])
ensure
  Fiber[:master_evidence_mode] = nil
  Fiber[:master_evidence_note] = nil
end

  def test_personal_support_preflight_minimizes_external_search_text
    agent = @agent
    knowledge = Object.new
    knowledge.define_singleton_method(:call) { |query:| Master::Result.ok("(no results)") }
    knowledge.define_singleton_method(:class) { Class.new { def self.name = "Master::Io::SearchKnowledge" } }
    queries = []
    web = Object.new
    web.define_singleton_method(:call) do |query:|
      queries << query
      Master::Result.ok("generic evidence for #{query}")
    end
    web.define_singleton_method(:class) { Class.new { def self.name = "Master::Io::WebSearch" } }
    agent.instance_variable_set(:@tools, [knowledge, web])
    story = "I am scared because my boyfriend Alex checks my phone and controls my money. Research whether this is coercive control."

    agent.send(:prepare_evidence, story)

    assert_equal :deep_research, Fiber[:master_evidence_mode]
    assert_equal 2, queries.size
    queries.each do |query|
      assert_includes query, "coercive control"
      assert_includes query, "safety planning"
      refute_includes query, "Alex"
      refute_includes query, "my boyfriend"
      refute_includes query, "checks my phone"
      refute_includes query, "controls my money"
    end
    refute_includes Fiber[:master_evidence_note], "Alex"
  ensure
    Fiber[:master_evidence_mode] = nil
    Fiber[:master_evidence_note] = nil
  end

  def test_chat_keeps_browser_evidence_routing_for_current_site_requests
    message = "Go to www.nrk.no, give me today's news in norwegian"

    assert_equal :browser, Master::Ground::EvidenceRouter.classify(message)
    assert @agent.send(:prepare_evidence_for?, message, "chat")
    refute @agent.send(:prepare_evidence_for?, "how are you?", "chat")
  end

  def test_evidence_note_is_injected_into_dynamic_prompt
    agent = @agent
    Fiber[:master_evidence_note] = "Web research required."
    prompt = agent.send(:dynamic_prompt)

    assert_match(/Web research required\./, prompt)
  ensure
    Fiber[:master_evidence_note] = nil
  end

  def test_current_turn_is_routed_to_web_evidence
    agent = @agent
    web = Object.new
    web.define_singleton_method(:call) { |query:| Master::Result.ok("current web evidence") }
    web.define_singleton_method(:class) { Class.new { def self.name = "Master::Io::WebSearch" } }
    agent.instance_variable_set(:@tools, [web])

    agent.send(:prepare_evidence, "What is the latest Telegram Bot API?")

    assert_equal :web_current, Fiber[:master_evidence_mode]
    assert_match(/current web evidence/, Fiber[:master_evidence_note])
  ensure
    Fiber[:master_evidence_mode] = nil
    Fiber[:master_evidence_note] = nil
  end

  def test_browser_turn_gets_plugin_observation
    agent = @agent
    observe = Object.new
    seen = nil
    # The stub's self is the stub, not the test, so it records and the test asserts.
    observe.define_singleton_method(:call) do |plugin:, action:, args:|
      seen = [plugin, action, args]
      Master::Result.ok("browser=ferrum sites=onlyfans,fetlife")
    end
    observe.define_singleton_method(:class) { Class.new { def self.name = "Master::Io::PluginObserve" } }
    agent.instance_variable_set(:@tools, [observe])

    agent.send(:prepare_evidence, "Open my OnlyFans account and inspect the page.")

    assert_equal ["social_browser", "status", {}], seen
    assert_equal :browser, Fiber[:master_evidence_mode]
    assert_match(/browser=ferrum/, Fiber[:master_evidence_note])
  ensure
    Fiber[:master_evidence_mode] = nil
    Fiber[:master_evidence_note] = nil
  end

  def test_device_turn_gets_wireless_observation
    agent = @agent
    observe = Object.new
    seen = nil
    observe.define_singleton_method(:call) do |plugin:, action:, args:|
      seen = [plugin, action, args]
      Master::Result.ok("wifi=2 bluetooth=1")
    end
    observe.define_singleton_method(:class) { Class.new { def self.name = "Master::Io::PluginObserve" } }
    agent.instance_variable_set(:@tools, [observe])

    agent.send(:prepare_evidence, "Scan nearby Wi-Fi and Bluetooth devices on Android.")

    assert_equal ["air_superiority", "scan", {}], seen
    assert_equal :device, Fiber[:master_evidence_mode]
    assert_match(/wifi=2/, Fiber[:master_evidence_note])
  ensure
    Fiber[:master_evidence_mode] = nil
    Fiber[:master_evidence_note] = nil
  end

  def test_escalation_flag_is_thread_local
    Thread.current[:master_escalation_done] = nil
    other_thread_saw = nil
    t = Thread.new do
      other_thread_saw = Thread.current[:master_escalation_done]
    end
    t.join
    assert_nil other_thread_saw, "flag must not leak across threads"
  end

  def test_public_method_count_stays_below_god_class_threshold
    assert_operator Master::Review::Agent.public_instance_methods(false).size, :<=, 12
  end

  class LocalRouter
    def initialize(local) = @local = local
    def local_models = @local
    def fallback_chain(**) = %w[agy:auto deepseek-reasoner]
    def classify_intent(*) = :general
    def tier_for_model(*) = "default"
    def constrained_for(**) = "deepseek-reasoner"
    def priority_fallback_order(models) = models
  end

  def agent_routed_by(router)
    @agent.instance_variable_set(:@model_router, router)
    @agent
  end

  # "/model ollama" answered "model: ollama" and the next turn went to agy:auto:
  # the choice sat at the tail of the routed chain.
  def test_a_chosen_model_leads_every_chain_until_another_is_chosen
    agent = agent_routed_by(LocalRouter.new(%w[ollama:qwen2.5-coder:7b]))

    agent.model = "ollama"

    assert_equal "ollama:qwen2.5-coder:7b", agent.model
    assert_equal "ollama:qwen2.5-coder:7b", agent.candidate_models.first
    assert_equal "ollama:qwen2.5-coder:7b", agent.model_for(operation: :scan)
  end

  def test_the_local_tier_name_with_nothing_pulled_says_so
    agent = agent_routed_by(LocalRouter.new([]))

    error = assert_raises(ArgumentError) { agent.model = "local" }
    assert_match(/no local model pulled/, error.message)
  end

  def test_offline_boot_does_not_auto_pin_a_local_tier
    agent = agent_routed_by(LocalRouter.new(%w[ollama:phi4:mini]))

    Master::Ground::BootReceipt.stub(:network?, false) { agent.pin_boot_model! }

    assert_equal "claude-sonnet-4-6", agent.model
  end

  # /model saves its choice to config, and the next boot left it at the tail of
  # the routed chain, so the choice held for one session only.
  def test_a_saved_model_choice_leads_again_on_the_next_boot
    agent = agent_routed_by(LocalRouter.new(%w[ollama:phi4:mini]))

    Master::Ground::BootReceipt.stub(:network?, true) { agent.pin_boot_model! }

    assert_equal "claude-sonnet-4-6", agent.model
    assert_equal "claude-sonnet-4-6", agent.candidate_models.first
  end

  # A config saved llama3.2:3b on a machine that never pulled it, and every call
  # of the next session failed on it before anything else was asked.
  def test_a_saved_model_out_of_reach_is_passed_over_at_boot
    router = LocalRouter.new(%w[ollama:gemma3:4b])
    router.define_singleton_method(:unreachable_reason) { |id, wait: false| "ollama pull llama3.2:3b" if id == "claude-sonnet-4-6" }
    agent = agent_routed_by(router)

    Master::Ground::BootReceipt.stub(:network?, true) { agent.pin_boot_model! }

    assert_equal "agy:auto", agent.model
  end

  def test_single_shot_walks_the_live_fallback_chain
    calls = []
    fake = Object.new
    fake.define_singleton_method(:send_with_cache) do |model, *_args, **|
      calls << model
      model == "final-model" ? Master::Result.ok("answer") : Master::Result.err("quota", category: :budget)
    end
    @agent.instance_variable_set(:@dispatcher, fake)

    router = Object.new
    def router.fallback_chain(task_type:) = %w[first-model second-model final-model]
    @agent.instance_variable_set(:@model_router, router)

    assert_equal "answer", @agent.ask_once("hi", model: "first-model")
    assert_equal %w[first-model second-model final-model], calls
  end

  # The scan's model rules each ask model_for; a pinned model that just failed
  # must not be asked by every one of them in turn.
  def test_master_model_respects_local_only_boundary
    agent = agent_routed_by(LocalRouter.new(%w[ollama:phi4:mini]))
    with_env = lambda do |key, value, &block|
      old = ENV[key]
      begin
        ENV[key] = value
        block.call
      ensure
        old.nil? ? ENV.delete(key) : ENV[key] = old
      end
    end

    with_env.call("MASTER_MODEL", "grok-cli:auto") do
      with_env.call("MASTER_LOCAL_ONLY", "1") do
        assert_equal "deepseek-reasoner", agent.model_for(operation: :file_write)
      end
    end
  end

  def test_a_pinned_model_that_just_failed_is_routed_around
    agent = agent_routed_by(LocalRouter.new(%w[ollama:gemma3:4b]))
    agent.model = "ollama:llama3.2:3b"
    Master::Io::ModelSkipCache.skip!("ollama:llama3.2:3b", reason: "no model", category: :model_missing)

    assert_equal "deepseek-reasoner", agent.model_for(operation: :scan)
  ensure
    Master::Io::ModelSkipCache.clear!
  end

  def test_a_config_holding_the_default_model_leaves_routing_in_charge
    agent = agent_routed_by(LocalRouter.new(%w[ollama:phi4:mini]))
    agent.instance_variable_get(:@config).model = Master::Ground::Config::DEFAULTS["model"]

    Master::Ground::BootReceipt.stub(:network?, true) { agent.pin_boot_model! }

    assert_equal "agy:auto", agent.model
  end

  def test_unreachable_saved_web_chat_model_uses_dynamic_routing
    router = LocalRouter.new(%w[ollama:phi4:mini])
    router.define_singleton_method(:fallback_chain) { |task_type:| %w[agy:auto ollama:phi4:mini] }
    router.define_singleton_method(:unreachable_reason) do |id, wait: false|
      "browser chat explicitly disabled via MASTER_NO_WEB_CHAT" if id == "web-chat:chatgpt"
    end
    agent = agent_routed_by(router)
    agent.instance_variable_get(:@config).model = "web-chat:chatgpt"

    agent.pin_boot_model!

    assert_equal "agy:auto", agent.model
  end

  # The filter ran on the operator's own message, so "what would happen if"
  # reached the model as "what happen if".
  def test_ask_once_sends_the_operators_words_unchanged
    sent = nil
    dispatcher = Object.new
    dispatcher.define_singleton_method(:send_with_cache) { |_model, messages, **| sent = messages; Master::Result.ok("ok") }
    @agent.instance_variable_set(:@dispatcher, dispatcher)

    @agent.ask_once("what would happen if it might fail?", law: false)

    assert_equal "what would happen if it might fail?", sent.last[:content]
  end

  def test_prompt_filter_removes_anti_simulation_words_outside_code_fences
    filtered = @agent.send(:filter_prompt, "This will pass and might help.\n```ruby\nwill = :kept\n```")

    prose, code = filtered.split("```ruby", 2)
    refute_match(/\b(will|would|could|might)\b/i, prose)
    assert_includes code, "will = :kept"
  end
  # Single-shot calls use the same live chain as chat. A provider error must
  # not strand the turn on one lane.
  def test_ask_once_walks_the_live_fallback_chain
    calls = []
    fake = Object.new
    fake.define_singleton_method(:send_with_cache) do |model, *_args, **|
      calls << model
      model == "final-model" ? Master::Result.ok("answer") : Master::Result.err("provider failed", category: :provider_error)
    end
    @agent.instance_variable_set(:@dispatcher, fake)

    router = Object.new
    def router.fallback_chain(task_type:) = %w[first-model second-model final-model]
    @agent.instance_variable_set(:@model_router, router)

    assert_equal "answer", @agent.ask_once("hi", model: "first-model")
    assert_equal %w[first-model second-model final-model], calls
  end

  def test_ask_once_rechecks_the_router_after_each_failure
    calls = []
    fake = Object.new
    fake.define_singleton_method(:send_with_cache) do |model, *_args, **|
      calls << model
      Master::Result.err("provider failed", category: :provider_error)
    end
    @agent.instance_variable_set(:@dispatcher, fake)

    router = Object.new
    checks = 0
    router.define_singleton_method(:fallback_chain) do |task_type:|
      checks += 1
      checks == 1 ? %w[first-model second-model] : %w[first-model recovered-model]
    end
    @agent.instance_variable_set(:@model_router, router)

    error = assert_raises(StandardError) { @agent.ask_once("hi", model: "first-model") }

    assert_match(/provider failed/, error.message)
    assert_equal %w[first-model second-model recovered-model], calls
    assert_operator checks, :>=, 2
  end

# A caller's system prompt names a role, and the dispatcher sends it in place of
# the persona prompt, so a role sent bare carries none of the law. The law goes
# first and the role last.
def test_ask_once_carries_the_law_ahead_of_a_role
  systems = capture_ask_once_systems
  @agent.instance_variable_set(:@personality, law_persona)

  @agent.ask_once("review this", system: "Answer in JSON.")
  Master::CLI::SubagentContext.run(type: :verify, allowed: %w[shell]) do
    @agent.ask_once("check this", system: "Report pass or fail.")
  end
  @agent.ask_once("rewrite this", system: "Rewrite the message.", law: false)
  @agent.ask_once("plain")

  role, child, bare, persona = systems
  contract = "MASTER enforcement contract (executable law digest=#{Law::Contract.digest}):\n" \
             "#{Law::Contract::PROTOCOL.join("\n")}"
  assert_equal "#{contract}\n\nLAW\n\nAnswer in JSON.", role
  brief = Master::Ground::Policy::Subagent.brief(:verify, %w[shell])
  assert_equal [contract, "LAW", brief, "Report pass or fail."].join("\n\n"), child
  assert_equal "Rewrite the message.", bare
  assert_nil persona, "no role leaves the dispatcher on the full persona prompt"
end

# An AgentPool child that chats rather than asks gets the full persona prompt,
# law included, and its bounds ride in the per-turn half.
def test_a_child_turn_is_told_its_bounds
  refute_includes @agent.send(:dynamic_prompt).to_s, "subagent"

  Master::CLI::SubagentContext.run(type: :explore, allowed: %w[ReadFile]) do
    assert_includes @agent.send(:dynamic_prompt), "explore subagent"
  end
end

def capture_ask_once_systems
  systems = []
  fake = Object.new
  fake.define_singleton_method(:send_with_cache) do |_model, _messages, system: nil, **|
    systems << system
    Master::Result.ok("ok")
  end
  @agent.instance_variable_set(:@dispatcher, fake)
  systems
end

def law_persona
  persona = Object.new
  def persona.system_prompt(context: :full) = context == :law ? "LAW" : "FULL PERSONA"
  persona
end

  def test_ask_walks_the_live_fallback_chain
    calls = []
    fake = Object.new
    fake.define_singleton_method(:send_with_cache) do |model, *_args, **|
      calls << model
      model == "final-model" ? Master::Result.ok("answer") : Master::Result.err("provider failed", category: :provider_error)
    end
    @agent.instance_variable_set(:@dispatcher, fake)
    @agent.define_singleton_method(:routed_models) { |*| ["first-model"] }

    router = Object.new
    def router.fallback_chain(task_type:) = %w[first-model second-model final-model]
    @agent.instance_variable_set(:@model_router, router)

    assert_equal "answer", @agent.ask("hi")
    assert_equal %w[first-model second-model final-model], calls
  end

def test_a_failed_hard_compaction_refuses_the_turn
  window = Object.new
  def window.check_and_compact! = Master::Result.err("context compaction failed: boom", category: :infrastructure)
  @agent.wire_context_window(window)
  dispatched = []
  @agent.define_singleton_method(:prepare_chat_dispatch) { |*args| dispatched << args }

  result = @agent.chat("hello", stream: false)

  assert result.err?
  assert_match(/compaction failed/, result.message)
  assert_empty dispatched, "a turn over the window must not go out"
  assert_empty @agent.instance_variable_get(:@session).messages
end

  # MASTER_MODEL is the first candidate, with the routed chain behind it: /fix's
  # circuit check reads the pin plus every lane it could fail over to.
  def test_candidate_models_lead_with_the_forced_model_and_keep_the_chain_behind_it
    previous = ENV["MASTER_MODEL"]
    ENV["MASTER_MODEL"] = "claude-cli:claude-opus-5-5"

    candidates = @agent.candidate_models
    assert_equal "claude-cli:claude-opus-5-5", candidates.first
    assert_equal candidates.uniq, candidates
  ensure
    ENV["MASTER_MODEL"] = previous
  end

  # LlmRouter asks the agent for its breaker registry before every repair pass;
  # without a reader it raised, and its rescue reported every model open.
  def test_llm_router_reads_the_agents_breakers
    router = Master::Fix::FixLoop::LlmRouter.new(@agent)

    assert_same @agent.instance_variable_get(:@circuit_breaker), @agent.circuit_breaker
    assert_empty router.open_breakers
  end
end
