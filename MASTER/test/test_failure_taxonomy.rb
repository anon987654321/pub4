# frozen_string_literal: true

require_relative "test_helper"

class TestFailureTaxonomy < Minitest::Test
  def test_classifies_transient_errors
    taxonomy = Master::Ground::FailureTaxonomy.new
    info = taxonomy.handle(StandardError.new("rate limit exceeded"))
    assert_equal :transient, info[:category]
    assert_equal "exponential_backoff", info[:strategy]
    assert_operator info[:max_retries].to_i, :>, 0
  end

  def test_classifies_permanent_errors
    taxonomy = Master::Ground::FailureTaxonomy.new
    info = taxonomy.handle(StandardError.new("syntax error at line 3"))
    assert_equal :permanent, info[:category]
    assert_equal "fail_fast", info[:strategy]
    assert_equal 0, info[:max_retries].to_i
  end

  def test_classifies_ambiguous_errors
    taxonomy = Master::Ground::FailureTaxonomy.new
    info = taxonomy.handle(StandardError.new("partial write detected"))
    assert_equal :ambiguous, info[:category]
    assert_equal "human_intervention", info[:strategy]
  end
end