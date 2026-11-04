# frozen_string_literal: true

require "test_helper"

# posts#feed rendered its posts as bare siblings rather than the
# ul.post-card-list posts#index uses, and a reader who follows no one got
# an empty page with no word about why.
class FeedListTest < ActionDispatch::IntegrationTest
  setup do
    email = "fl-#{SecureRandom.hex(4)}@example.test"
    @user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
  end

  test "an empty feed says how to fill it" do
    get feed_posts_path
    assert_response :success
    assert_select ".empty-state", text: /#{I18n.t("empty.no_feed_posts")}/
    assert_select ".empty-state a[href=?]", posts_path
  end

  test "feed posts are list items" do
    Post.create!(user: @user, body: "Ny jakke")
    get feed_posts_path
    assert_select "ul.post-card-list > li", 1
    assert_select ".empty-state", 0
  end
end
