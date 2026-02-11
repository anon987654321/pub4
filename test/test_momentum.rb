# frozen_string_literal: true

require_relative "test_helper"

class TestMomentum < Minitest::Test
  def setup
    MASTER::Momentum.instance_variable_set(:@state, MASTER::Momentum.fresh)
  end

  def test_fresh_state
    state = MASTER::Momentum.fresh
    assert_equal 0, state[:xp]
    assert_equal 1, state[:level]
    assert_equal 0, state[:streak]
    assert_empty state[:achievements]
  end

  def test_award_increases_xp
    before = MASTER::Momentum.state[:xp]
    result = MASTER::Momentum.award(:chat)
    assert result[:xp_gained] > 0
    assert MASTER::Momentum.state[:xp] > before
  end

  def test_title_at_level_1
    title = MASTER::Momentum.title
    assert_equal "Novice", title
  end

  def test_streak_multiplier_starts_at_one
    mult = MASTER::Momentum.streak_multiplier
    assert_equal 1.0, mult
  end

  def test_xp_values_defined
    assert MASTER::Momentum::XP[:chat]
    assert MASTER::Momentum::XP[:refactor]
    assert MASTER::Momentum::XP[:evolve]
  end
end
