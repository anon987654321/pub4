# frozen_string_literal: true

require "minitest/autorun"
require "master"

# The context budget adapts to the host so a ~1GB VPS compacts sooner and never
# feeds the OOM-killer. budget_for is the pure policy; these pin its edges.
class HostBudgetTest < Minitest::Test
  M = Master::Core::Memory

  def test_constrained_host_gets_the_small_budget
    assert_equal M::CONSTRAINED_BUDGET, M.budget_for(1024)
    assert_equal M::CONSTRAINED_BUDGET, M.budget_for(M::CONSTRAINED_MB)
  end

  def test_roomy_host_gets_the_generous_budget
    assert_equal M::GENEROUS_BUDGET, M.budget_for(M::CONSTRAINED_MB + 1)
    assert_equal M::GENEROUS_BUDGET, M.budget_for(16_384)
  end

  def test_unknown_memory_stays_generous
    assert_equal M::GENEROUS_BUDGET, M.budget_for(nil)
  end

  def test_default_memory_uses_a_positive_budget
    assert_operator M.new.instance_variable_get(:@budget), :>, 0
  end

  def test_compact_drops_oldest_acts_once_the_budget_is_exceeded
    memory = M.new(budget: 80, summarize: ->(dropped) { "SUM #{dropped.length}" })
    memory.note(:goal, "do the thing")
    12.times do |i|
      memory.record(
        Master::Core::Effect.exec(["echo", "act-#{i}-xxxxxxxx"]),
        Master::Core::Observation.no("obs-#{i}-xxxxxxxx"),
      )
    end

    ctx = memory.context
    text = ctx.map(&:text).join
    assert_operator text.length, :<=, 80 + 20, "compact left #{text.length} chars"
    assert ctx.any? { |e| e.text.start_with?("SUM") }, "oldest turns were not summarised"
  end
end
