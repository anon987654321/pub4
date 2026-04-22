# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "json"
require_relative "../lib/master"

class TestLearningQuality < Minitest::Test
  def test_tiers_constant_exists
    assert defined?(MASTER::LearningQuality::TIERS)
    assert MASTER::LearningQuality::TIERS.key?(:promote)
    assert MASTER::LearningQuality::TIERS.key?(:keep)
    assert MASTER::LearningQuality::TIERS.key?(:demote)
    assert MASTER::LearningQuality::TIERS.key?(:retire)
  end

  def test_minimum_applications_constant
    assert_equal 3, MASTER::LearningQuality::MINIMUM_APPLICATIONS
  end

  def test_evaluate_unrated_insufficient_applications
    pattern = { "applications" => 2, "successes" => 2, "failures" => 0 }
    
    tier = MASTER::LearningQuality.evaluate(pattern)
    assert_equal :unrated, tier
  end

  def test_evaluate_promote_tier
    pattern = { "applications" => 10, "successes" => 10, "failures" => 0 }
    
    tier = MASTER::LearningQuality.evaluate(pattern)
    assert_equal :promote, tier
  end

  def test_evaluate_keep_tier
    pattern = { "applications" => 10, "successes" => 7, "failures" => 3 }
    
    tier = MASTER::LearningQuality.evaluate(pattern)
    assert_equal :keep, tier
  end

  def test_evaluate_demote_tier
    pattern = { "applications" => 10, "successes" => 3, "failures" => 7 }
    
    tier = MASTER::LearningQuality.evaluate(pattern)
    assert_equal :demote, tier
  end

  def test_evaluate_retire_tier
    pattern = { "applications" => 10, "successes" => 1, "failures" => 9 }
    
    tier = MASTER::LearningQuality.evaluate(pattern)
    assert_equal :retire, tier
  end

  def test_calculate_success_rate
    pattern = { "successes" => 8, "failures" => 2 }
    
    rate = MASTER::LearningQuality.calculate_success_rate(pattern)
    assert_equal 0.8, rate
  end

  def test_calculate_success_rate_zero_total
    pattern = { "successes" => 0, "failures" => 0 }
    
    rate = MASTER::LearningQuality.calculate_success_rate(pattern)
    assert_equal 0.0, rate
  end

  def test_tier_method_delegates_to_evaluate
    pattern = { "applications" => 10, "successes" => 10, "failures" => 0 }
    
    tier = MASTER::LearningQuality.tier(pattern)
    assert_equal :promote, tier
  end

  def test_prune_returns_result
    skip "Requires LearningFeedback DB setup"
    
    # This would test actual pruning, but requires complex DB setup
    # result = MASTER::LearningQuality.prune!
    # assert result.ok?
  end
end
