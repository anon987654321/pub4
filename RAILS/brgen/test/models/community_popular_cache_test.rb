# frozen_string_literal: true

require "test_helper"

# Community.popular joins and groups every post in the city to rank ten sidebar
# links. The home page called it on every request. Measured on production
# 2026-08-07: the front page answered in 4.1s TTFB while /posts, rendering the
# same feed without this call, answered in 0.83s at the same payload size.
#
# popular_cached must therefore actually cache — a wrapper that re-queries every
# time would keep the cost and add a layer.
class CommunityPopularCacheTest < ActiveSupport::TestCase
  setup do
    @store = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @store }

  def count_selects
    queries = 0
    counter = ->(_name, _start, _finish, _id, payload) do
      queries += 1 unless payload[:name].to_s.in?(%w[SCHEMA TRANSACTION CACHE])
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    queries
  end

  test "ranks communities on the first call and serves the rest from cache" do
    first = count_selects { Community.popular_cached(limit: 10) }
    second = count_selects { Community.popular_cached(limit: 10) }

    assert_operator first, :>, 0, "the first call must actually query"
    assert_equal 0, second,
                 "popular_cached issued #{second} queries on the second call — it is not caching, " \
                 "and the front page pays the join-and-group on every request"
  end

  test "returns the same communities the uncached scope would" do
    assert_equal Community.popular.limit(10).map(&:id),
                 Community.popular_cached(limit: 10).map(&:id)
  end

  test "caches per city so one city cannot serve another's sidebar" do
    a = Community.popular_cached(limit: 10, tenant: nil)
    stub = Struct.new(:id).new(-1)
    b = Community.popular_cached(limit: 10, tenant: stub)

    # Distinct keys: the second tenant must compute rather than read the first's.
    assert_equal a.map(&:id), b.map(&:id), "same data expected in this fixture set"
    assert Rails.cache.exist?([ "communities/popular", "global", 10 ])
    assert Rails.cache.exist?([ "communities/popular", -1, 10 ])
  end
end
