# frozen_string_literal: true

require_relative "test_helper"

class TestModelSkipCache < Minitest::Test
  def setup
    Master::Io::ModelSkipCache.clear!
    @prev = ENV["MASTER_FALLBACK_SKIP_TTL_MS"]
    ENV["MASTER_FALLBACK_SKIP_TTL_MS"] = "5000"
  end

  def teardown
    ENV["MASTER_FALLBACK_SKIP_TTL_MS"] = @prev
    Master::Io::ModelSkipCache.clear!
  end

  def test_skip_and_filter
    Master::Io::ModelSkipCache.skip!("m1", reason: "rate limit", category: :rate_limit)
    assert Master::Io::ModelSkipCache.skipped?("m1")
    filtered = Master::Io::ModelSkipCache.filter(%w[m1 m2])
    assert_equal %w[m2], filtered
  end

  def test_skip_ttl_from_env
    assert_equal 5000, Master::Io::ModelSkipCache.skip_ttl_ms
  end
end
