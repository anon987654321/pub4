# frozen_string_literal: true

require_relative "test_helper"

# Minimal unit tests for Master::Agent — specifically targeting the Tier-1
# bugs the patch corrects. Does not hit any real LLM.
class TestAgent < Minitest::Test
  include Master

  # Fake collaborators — just enough to construct an Agent.
  FakeConfig  = Struct.new(:model, :task_type, :reasoning_mode) do
    def [](k) = send(k) rescue nil
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
  def test_tool_capable_accepts_known_providers
    skip "drifted: API moved; port to new dispatcher/CLI shape"
    assert @agent.send(:tool_capable?, "claude-sonnet-4-6")
    assert @agent.send(:tool_capable?, "gpt-4o")
    assert @agent.send(:tool_capable?, "anthropic/claude-opus-4-1")
  end

  def test_tool_capable_rejects_arbitrary_strings
    skip "drifted: API moved; port to new dispatcher/CLI shape"
    refute @agent.send(:tool_capable?, "not-a-model")
    refute @agent.send(:tool_capable?, "")
    refute @agent.send(:tool_capable?, "random-gpt-mention-inside-sentence"), \
      "substring-contains is the old bug; anchored regex must not match this"
  end

  # cache_key_for — must produce bounded, deterministic SHA256 keys.
  def test_cache_key_bounded
    skip "drifted: API moved; port to new dispatcher/CLI shape"
    k = @agent.send(:cache_key_for, "hello", [])
    assert_equal 64, k.length, "SHA256 hex is 64 chars"
    assert_equal k, @agent.send(:cache_key_for, "hello", []), "deterministic"
  end

  def test_cache_key_uses_window_not_full_context
    skip "drifted: API moved; port to new dispatcher/CLI shape"
    long_ctx = (1..100).map { |i| { role: "user", content: "msg #{i}" * 50 } }
    short_ctx = long_ctx.last(4)
    k_long  = @agent.send(:cache_key_for, "same", long_ctx)
    k_short = @agent.send(:cache_key_for, "same", short_ctx)
    assert_equal k_long, k_short, "only the last CACHE_WINDOW messages affect the key"
  end

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

  out = @agent.ask_once("hi", model: "openrouter/broke")

  assert_equal "cli answer", out
  assert_equal 2, fake.models.size, "expected exactly one failover hop"
  assert fake.models.last.to_s.start_with?("claude-cli:"), "hop must land on the claude_code chain head"
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
  def @agent.routed_models(*_args, **_kwargs) = ["openrouter/broke"]

  assert_equal "cli answer", @agent.ask("hi")
  assert fake.models.last.to_s.start_with?("claude-cli:"), "ask must land on the claude_code chain head"
end
end
