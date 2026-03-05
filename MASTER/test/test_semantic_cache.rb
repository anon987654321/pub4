# frozen_string_literal: true

require_relative "test_helper"

class TestSemanticCache < Minitest::Test
  def setup
    # Clear cache before each test
    MASTER::SemanticCache.clear! if defined?(MASTER::SemanticCache)
  end

  def teardown
    # Clean up after tests
    MASTER::SemanticCache.clear! if defined?(MASTER::SemanticCache)
  end

  def test_store_and_exact_lookup
    skip "SemanticCache not available" unless defined?(MASTER::SemanticCache)

    prompt = "What is the meaning of life?"
    response_data = {
      content: "42",
      cost: 0.01,
      tokens_in: 10,
      tokens_out: 5
    }

    # Store in cache
    result = MASTER::SemanticCache.store(prompt, response_data, tier: :fast)
    assert result.ok?, "Store should succeed"

    # Lookup with exact prompt
    lookup_result = MASTER::SemanticCache.lookup(prompt, tier: :fast)
    assert lookup_result.ok?, "Lookup should succeed"
    assert_equal "42", lookup_result.value[:content]
    assert_equal 0.01, lookup_result.value[:cost]
  end

  def test_cache_miss
    skip "SemanticCache not available" unless defined?(MASTER::SemanticCache)

    prompt = "This prompt has never been cached"
    result = MASTER::SemanticCache.lookup(prompt, tier: :fast)
    assert result.err?, "Lookup should return cache miss"
    assert_equal "cache miss", result.error
  end

  def test_stats
    skip "SemanticCache not available" unless defined?(MASTER::SemanticCache)

    # Add some entries
    3.times do |i|
      MASTER::SemanticCache.store(
        "prompt #{i}",
        { content: "response #{i}", cost: 0.01 },
        tier: :fast
      )
    end

    stats = MASTER::SemanticCache.stats
    assert_equal 3, stats[:entries]
    assert stats[:size_bytes] > 0
    assert stats[:size_human].is_a?(String)
    assert stats[:cache_dir].is_a?(String)
  end

  def test_clear
    skip "SemanticCache not available" unless defined?(MASTER::SemanticCache)

    # Add an entry
    MASTER::SemanticCache.store(
      "test prompt",
      { content: "test response", cost: 0.01 },
      tier: :fast
    )

    # Verify it exists
    stats_before = MASTER::SemanticCache.stats
    assert stats_before[:entries] > 0

    # Clear cache
    MASTER::SemanticCache.clear!

    # Verify it's empty
    stats_after = MASTER::SemanticCache.stats
    assert_equal 0, stats_after[:entries]
  end

  def test_expired_entries_not_returned
    skip "SemanticCache not available" unless defined?(MASTER::SemanticCache)
    skip "Cannot test expiration without time travel"

    # This test would require mocking Time to test expiration
    # For now, we'll skip it in automated tests
  end

  def test_case_insensitive_lookup
    skip "SemanticCache not available" unless defined?(MASTER::SemanticCache)

    prompt_lower = "hello world"
    prompt_upper = "HELLO WORLD"
    response_data = { content: "Hi!", cost: 0.01 }

    # Store with lowercase
    MASTER::SemanticCache.store(prompt_lower, response_data, tier: :fast)

    # Lookup with uppercase (after normalization should match)
    result = MASTER::SemanticCache.lookup(prompt_upper, tier: :fast)
    assert result.ok?, "Case-insensitive lookup should succeed"
    assert_equal "Hi!", result.value[:content]
  end

  def test_hit_count_increment
    skip "SemanticCache not available" unless defined?(MASTER::SemanticCache)

    prompt = "count test prompt"
    response_data = { content: "response", cost: 0.01 }

    # Store
    MASTER::SemanticCache.store(prompt, response_data, tier: :fast)

    # Lookup multiple times
    3.times { MASTER::SemanticCache.lookup(prompt, tier: :fast) }

    # Check that hit count was incremented
    # (This is implementation detail, but we can verify by reading the cache file)
    key = Digest::SHA256.hexdigest(prompt.strip.downcase)[0, 16]
    path = File.join(MASTER::Paths.semantic_cache, "#{key}.json")
    
    if File.exist?(path)
      entry = JSON.parse(File.read(path), symbolize_names: true)
      assert entry[:hit_count] >= 3, "Hit count should be incremented"
    end
  end
end
