# frozen_string_literal: true

require "test_helper"

class SocialGuardsTest < ActionDispatch::IntegrationTest
  def user(prefix)
    User.strict_loading(false).create!(
      email_address: "#{prefix}-#{SecureRandom.hex(4)}@amber.test",
      password: "password123"
    )
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "an accepted connection can message" do
    alice = user("alice")
    bob = user("bob")
    Connection.create!(requester: alice, addressee: bob, status: "accepted")
    sign_in(alice)

    assert_difference "Message.count", 1 do
      post messages_path, params: { message: { recipient_id: bob.id, body: "Hei" } }
    end
  end

  test "a blocked connection cannot message" do
    alice = user("alice")
    bob = user("bob")
    Connection.create!(requester: alice, addressee: bob, status: "accepted").block!
    sign_in(alice)

    assert_no_difference "Message.count" do
      post messages_path, params: { message: { recipient_id: bob.id, body: "Hei" } }
    end
    assert_response :unprocessable_entity
  end

  test "the live streams index renders scheduled streams" do
    host = user("host")
    viewer = user("viewer")
    LiveStream.create!(user: host, title: "Høstgarderobe", status: "scheduled")
    sign_in(viewer)

    get live_streams_path

    assert_response :success
    assert_select "h1", I18n.t("live_streams.title")
    assert_select "a", "Høstgarderobe"
  end

  test "destroying another user's affiliate link is refused" do
    owner = user("owner")
    stranger = user("stranger")
    item = Item.create!(user: owner, title: "Kåpe", category: "Outerwear")
    link = item.affiliate_links.create!(merchant: "Cos", url: "https://example.com/coat")
    sign_in(stranger)

    assert_no_difference "AffiliateLink.count" do
      delete item_affiliate_link_path(item, link)
    end
    assert_response :not_found
  end

  test "the owner can destroy their own affiliate link" do
    owner = user("owner")
    item = Item.create!(user: owner, title: "Kåpe", category: "Outerwear")
    link = item.affiliate_links.create!(merchant: "Cos", url: "https://example.com/coat")
    sign_in(owner)

    assert_difference "AffiliateLink.count", -1 do
      delete item_affiliate_link_path(item, link)
    end
    assert_redirected_to item_path(item)
  end
end
