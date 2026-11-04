# frozen_string_literal: true

require "test_helper"

# Deleting a post redirected to the feed with no word that it had worked.
class PostDeleteNoticeTest < ActionDispatch::IntegrationTest
  test "deleting your post says so" do
    email = "pd-#{SecureRandom.hex(4)}@example.test"
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post session_path, params: { email_address: email, password: "password" }
    doomed = Post.create!(user:, body: "Feil bilde")

    delete post_path(doomed)
    assert_redirected_to posts_path
    assert_equal I18n.t("flash.post_deleted"), flash[:notice]
    assert_not Post.exists?(doomed.id)
  end
end
