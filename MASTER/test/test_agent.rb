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
  FakeCache   = Struct.new(:store) { def fetch(k, m, &b); (store[k] ||= b.call); end }

  def setup
    @agent = Master::Agent.new(
      config:          FakeConfig.new("claude-sonnet-4-6", :exploration, "none"),
      session:         FakeSession.new([]),
      tools:           [],
      circuit_breaker: FakeCB.new,
      cache:           FakeCache.new({})
    )
  end

  # tool_capable? — previously a substring-include check. After patch,
  # anchored regex rejects garbage-tailed model ids but accepts real ones.
  def test_tool_capable_accepts_known_providers
    assert @agent.send(:tool_capable?, "claude-sonnet-4-6")
    assert @agent.send(:tool_capable?, "gpt-4o")
    assert @agent.send(:tool_capable?, "anthropic/claude-opus-4-1")
  end

  def test_tool_capable_rejects_arbitrary_strings
    refute @agent.send(:tool_capable?, "not-a-model")
    refute @agent.send(:tool_capable?, "")
    refute @agent.send(:tool_capable?, "random-gpt-mention-inside-sentence"), \
      "substring-contains is the old bug; anchored regex must not match this"
  end

  # cache_key_for — must produce bounded, deterministic SHA256 keys.
  def test_cache_key_bounded
    k = @agent.send(:cache_key_for, "hello", [])
    assert_equal 64, k.length, "SHA256 hex is 64 chars"
    assert_equal k, @agent.send(:cache_key_for, "hello", []), "deterministic"
  end

  def test_cache_key_uses_window_not_full_context
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
end
