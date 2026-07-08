# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../core/master"

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
end
