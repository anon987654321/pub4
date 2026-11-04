# frozen_string_literal: true

require "test_helper"

# The comment heading read "Kommentarer (3)", a count in brackets after a
# fixed plural, rather than a counted phrase.
class PostCommentsHeadingTest < ActionDispatch::IntegrationTest
  test "the comment heading counts in words" do
    email = "ch-#{SecureRandom.hex(4)}@example.test"
    user = User.strict_loading(false).create!(email_address: email, password: "password")
    post_record = Post.create!(user:, body: "Ny jakke")

    get post_path(post_record, locale: "nb")
    assert_response :success
    assert_select "#comments h2", text: I18n.t("post.comments_heading", count: 0, locale: :nb)
    assert_no_match(/\(\d+\)/, css_select("#comments h2").text)
  end
end
