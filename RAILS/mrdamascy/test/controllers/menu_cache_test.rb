# frozen_string_literal: true

require "test_helper"

# The menu's dish cards are fragment-cached: a second visit reads them, a
# changed dish or another language writes afresh, and the add form is
# never cached.
class MenuCacheTest < ActionDispatch::IntegrationTest
  setup do
    @item = seed_item!(seed_category!(seed_kitchen!))
    @was_caching = ActionController::Base.perform_caching
    ActionController::Base.perform_caching = true
    Rails.cache.clear
  end

  teardown { ActionController::Base.perform_caching = @was_caching }

  def fragment_writes(&)
    writes = []
    callback = ->(event) { writes << event.payload[:key] }
    ActiveSupport::Notifications.subscribed(callback, "write_fragment.action_controller", &)
    writes
  end

  test "a dish card is written once, then read, and rewritten when the dish changes" do
    assert_equal 1, fragment_writes { get root_url }.size
    assert_empty fragment_writes { get root_url }

    @item.update!(name: "Damaskus Kylling Shawarma XL")
    assert_equal 1, fragment_writes { get root_url }.size
    assert_includes response.body, "Damaskus Kylling Shawarma XL"
    assert_equal 1, fragment_writes { get root_url(locale: "en") }.size
  end

  test "the cached face of a card holds no form" do
    key = fragment_writes { get root_url }.sole
    cached = Rails.cache.read(key)

    assert_includes cached, @item.name
    assert_not_includes cached, "<form", "the add form carries a per-visitor token and must stay live"
  end
end
