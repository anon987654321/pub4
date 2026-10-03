# frozen_string_literal: true

require "test_helper"

# The post partial is fragment-cached. Its key used to include Current.user&.id,
# and brgen creates a fresh guest user for every request without a session
# cookie — so each anonymous visitor got their own copy of every card. For
# crawler traffic the cache never hit once, and every visit wrote one entry per
# post into the store.
#
# Development has caching off, so none of this is visible when profiling
# locally by eye; this test turns the store on for its duration and counts
# writes, which is the only way it shows up short of production.
class PostFragmentCacheTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"

    @previous_store = Rails.cache
    @previous_flag = ActionController::Base.perform_caching
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    ActionController::Base.perform_caching = true
  end

  teardown do
    Rails.cache = @previous_store
    ActionController::Base.perform_caching = @previous_flag
    ActsAsTenant.current_tenant = nil
  end

  def cache_writes
    writes = 0
    sub = ActiveSupport::Notifications.subscribe("cache_write.active_support") { writes += 1 }
    yield
    writes
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  def seed_posts(count)
    author = User.strict_loading(false).create!(
      email_address: "frag-#{SecureRandom.hex(4)}@brgen.no", password: "password123", city: @city,
    )
    community = Community.create!(name: "Frag #{SecureRandom.hex(3)}", slug: "frag-#{SecureRandom.hex(4)}")
    count.times { |i| Post.create!(user: author, community:, title: "Frag #{i}", content: "…") }
  end

  # Each `get` here arrives without a cookie, so each one is a different guest —
  # exactly the crawler pattern. With the old key every visit re-wrote the whole
  # page's worth of fragments; with the vote-based key the second visit writes
  # nothing, because a guest who has not voted sees the same markup as the last
  # one who had not voted.
  test "a second anonymous visitor reuses the cached post fragments" do
    ActsAsTenant.with_tenant(@city) do
      seed_posts(8)

      first = cache_writes { get root_path }
      assert_response :success
      assert_operator first, :>, 0, "nothing was cached at all — the test proves nothing"

      reset!
      host! "brgen.no"
      second = cache_writes { get root_path }
      assert_response :success

      assert_operator second, :<, first,
                       "a different anonymous visitor re-wrote #{second} fragments (first visit wrote " \
                       "#{first}): the cache key still varies per guest user"
    end
  end
end
