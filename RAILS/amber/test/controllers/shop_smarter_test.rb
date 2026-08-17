# frozen_string_literal: true

require "test_helper"

class ShopSmarterTest < ActionDispatch::IntegrationTest
  def sign_in_as(email)
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: user.email_address, password: "password" }
    user
  end

  test "the page lists the affiliate links you attached to your own garments" do
    user = sign_in_as("shop-links@example.com")
    item = user.items.create!(title: "Wool coat", category: "Outerwear")
    item.affiliate_links.create!(merchant: "Vestiaire", url: "https://example.com/coat", commission_rate: 4.5)

    get shopping_list_items_path

    assert_response :success
    assert_select "#shop-affiliates"
    assert_select ".shop-links", text: /Vestiaire/
    # Commercial, user-supplied destinations do not get amber's endorsement.
    assert_select "a[href='https://example.com/coat'][rel~=sponsored][rel~=nofollow][rel~=noopener]"
  end

  test "another wardrobe's affiliate links stay out of yours" do
    other = User.strict_loading(false).create!(email_address: "shop-other@example.com", password: "password")
    other.items.create!(title: "Their coat", category: "Outerwear")
         .affiliate_links.create!(merchant: "SomeoneElse", url: "https://example.com/theirs")
    sign_in_as("shop-mine@example.com")

    get shopping_list_items_path

    assert_response :success
    assert_select "body", text: /SomeoneElse/, count: 0
  end

  test "duplicates are shown as the counterpart to a gap list" do
    user = sign_in_as("shop-dupes@example.com")
    3.times { |i| user.items.create!(title: "White shirt #{i}", category: "Tops", color: "white", material: "cotton", brand: "Uniqlo") }

    get shopping_list_items_path

    assert_response :success
    assert_select "#shop-duplicates"
  end

  test "the missing store feed is stated rather than left as an empty section" do
    sign_in_as("shop-feed@example.com")

    get shopping_list_items_path

    assert_response :success
    assert_select "#shop-feeds"
    assert_select ".shop-feed-note", text: /Net-a-porter|produktfeed/i
  end

  test "ShopTheLook names why the remote feed cannot answer" do
    # No token configured in test, so the first gate is the honest one.
    assert_equal :no_token, ShopTheLook.remote_unavailable_reason
    assert_not ShopTheLook.remote_available?
  end

  # This test used to assert :no_feed_client — the feed client lived in brgen's
  # app/services and was never loaded in amber, so a token in /etc/amber.env
  # passed the first gate and then silently did nothing. The client is
  # Shared::Tradedoubler now and amber loads it, so the same token reaches
  # something that can answer, and this asserts the reversal rather than being
  # deleted: it is the one behaviour the move was for.
  test "a configured token now reaches a feed client amber can load" do
    ENV["TRADEDOUBLER_TOKEN"] = "test-token"

    assert defined?(Shared::Tradedoubler), "the feed client must be loadable in amber"
    assert Shared::Tradedoubler.respond_to?(:deals)
    assert_not_equal :no_feed_client, ShopTheLook.remote_unavailable_reason
  ensure
    ENV.delete("TRADEDOUBLER_TOKEN")
  end

  test "remote suggestions stay empty and local links still surface" do
    user = sign_in_as("shop-suggest@example.com")
    item = user.items.create!(title: "Linen shirt", category: "Tops", brand: "Cos")
    item.affiliate_links.create!(merchant: "Cos", url: "https://example.com/shirt")

    suggestions = ShopTheLook.for_item(item.reload)

    assert_equal [ "saved" ], suggestions.map(&:source).uniq
    assert_empty ShopTheLook.remote_suggestions(item, limit: 6)
  end
end
