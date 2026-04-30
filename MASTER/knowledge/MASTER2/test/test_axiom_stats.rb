# frozen_string_literal: true

require_relative "test_helper"

class TestAxiomStats < Minitest::Test
  def test_stats_returns_data
    stats = MASTER::AxiomStats.stats
    
    refute stats[:error], "Stats should not have errors"
    assert stats[:total], "Should have total count"
    assert stats[:by_category], "Should have category breakdown"
    assert stats[:by_protection], "Should have protection breakdown"
  end

  def test_summary_format
    summary = MASTER::AxiomStats.summary
    
    assert_match /Language Axioms Summary/, summary
    assert_match /Total axioms:/, summary
    assert_match /By Category:/, summary
    assert_match /By Protection Level:/, summary
  end

  def test_category_counts
    stats = MASTER::AxiomStats.stats
    
    # These tests validate the exact axioms.yml content at time of writing.
    # If axioms.yml is intentionally updated, these assertions should be updated too.
    assert_equal 11, stats[:by_category]["engineering"]
    assert_equal 8, stats[:by_category]["structural"]
    assert_equal 6, stats[:by_category]["process"]
    assert_equal 5, stats[:by_category]["aesthetic"]
    assert_equal 4, stats[:by_category]["communication"]
    assert_equal 4, stats[:by_category]["meta"]
    assert_equal 3, stats[:by_category]["resilience"]
  end

  def test_protection_counts
    stats = MASTER::AxiomStats.stats
    
    # These tests validate the exact axioms.yml content at time of writing.
    # If axioms.yml is intentionally updated, these assertions should be updated too.
    assert_equal 40, stats[:by_protection]["PROTECTED"]
    assert_equal 1, stats[:by_protection]["ABSOLUTE"]
  end

  def test_total_axiom_count
    stats = MASTER::AxiomStats.stats
    
    # This validates the total count matches axioms.yml at time of writing.
    # 11 + 8 + 6 + 5 + 4 + 4 + 3 = 41
    assert_equal 41, stats[:total]
  end

  def test_top_categories
    top = MASTER::AxiomStats.top_categories(limit: 3)
    
    assert_equal 3, top.length
    assert_equal ["engineering", 11], top[0]
    assert_equal ["structural", 8], top[1]
    assert_equal ["process", 6], top[2]
  end
end
