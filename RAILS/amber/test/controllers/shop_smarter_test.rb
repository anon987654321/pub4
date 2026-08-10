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

  test "a configured token alone does not make the feed available in amber" do
    # Tradedoubler lives in brgen and is never loaded here, so a token set in
    # /etc/amber.env used to pass the first gate and then silently do nothing.
    ENV["TRADEDOUBLER_TOKEN"] = "test-token"

    assert_equal :no_feed_client, ShopTheLook.remote_unavailable_reason
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
