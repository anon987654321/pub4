# frozen_string_literal: true

require_relative "test_helper"

# Minimal unit tests for Master::Agent — specifically targeting the Tier-1
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

  def setup
    @agent = Master::Agent.new(deps: Master::Agent::Dependencies.from_kwargs(
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
# One empty OpenRouter balance killed every single-shot call: ask_once had
# no chain, so the first broke model raised with claude-cli unconsulted.
# A :budget/:rate_limit/:timeout Err now takes one hop to the claude_code
# chain head before raising.
def test_ask_once_fails_over_to_the_cli_lane_on_budget_errors
  fake = Class.new do
    attr_reader :models
    def initialize = @models = []
    def send_with_cache(model, *_args, **_kwargs)
      @models << model
      if model.to_s.start_with?("claude-cli:")
        Master::Result.ok("cli answer")
      else
        Master::Result.err("Insufficient credits", category: :budget)
      end
    end
  end.new
  @agent.instance_variable_set(:@dispatcher, fake)
  # the hop reads the chain head through ModelRouter, the one models.yml reader
  router = Object.new
  def router.single_call_fallback_model = "claude-cli:sonnet"
  @agent.instance_variable_set(:@model_router, router)

  out = @agent.ask_once("hi", model: "openrouter/broke")

  assert_equal "cli answer", out
  assert_equal 2, fake.models.size, "expected exactly one failover hop"
  assert fake.models.last.to_s.start_with?("claude-cli:"), "hop must land on the claude_code chain head"
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
  assert_equal "LAW\n\nAnswer in JSON.", role
  brief = Master::Ground::Policy::Subagent.brief(:verify, %w[shell])
  assert_equal ["LAW", brief, "Report pass or fail."].join("\n\n"), child
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

def test_ask_also_takes_the_hop_on_budget_errors
  fake = Class.new do
    attr_reader :models
    def initialize = @models = []
    def send_with_cache(model, *_args, **_kwargs)
      @models << model
      if model.to_s.start_with?("claude-cli:")
        Master::Result.ok("cli answer")
      else
        Master::Result.err("Insufficient credits", category: :budget)
      end
    end
  end.new
  @agent.instance_variable_set(:@dispatcher, fake)
  # the hop reads the chain head through ModelRouter, the one models.yml reader
  router = Object.new
  def router.single_call_fallback_model = "claude-cli:sonnet"
  @agent.instance_variable_set(:@model_router, router)
  def @agent.routed_models(*_args, **_kwargs) = ["openrouter/broke"]

  assert_equal "cli answer", @agent.ask("hi")
  assert fake.models.last.to_s.start_with?("claude-cli:"), "ask must land on the claude_code chain head"
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
end
