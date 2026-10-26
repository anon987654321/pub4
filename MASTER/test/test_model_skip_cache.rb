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

  def test_a_stated_wait_sets_the_park_and_a_shorter_one_never_shortens_it
    cache = Master::Io::ModelSkipCache
    cache.skip!("m1", reason: "429 Too Many Requests, retry after 6h", category: :rate_limit)
    long = cache.skipped_until_ms("m1")
    cache.skip!("m1", reason: "provider overloaded", category: :provider_error)

    assert_equal long, cache.skipped_until_ms("m1")
    assert_in_delta 6 * 3600 * 1000, long - (Time.now.to_f * 1000), 5000
  end

  def test_a_rate_limit_without_a_stated_wait_parks_briefly
    Master::Io::ModelSkipCache.skip!("m1", reason: "429", category: :rate_limit)
    until_ms = Master::Io::ModelSkipCache.skipped_until_ms("m1")

    assert_operator until_ms - (Time.now.to_f * 1000), :<=, Master::Io::ModelSkipCache.transient_skip_ttl_ms
  end

  def test_skip_ttl_from_env
    assert_equal 5000, Master::Io::ModelSkipCache.skip_ttl_ms
  end
end
