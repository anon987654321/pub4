# frozen_string_literal: true

require "test_helper"

class PostsControllerTest < ActionDispatch::IntegrationTest
  test "show renders without a strict_loading violation on post.user" do
    user = User.create!(email_address: "post-show-test-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    post = Post.create!(user:, title: "Regression fixture", content: "body")

    host! "brgen.no"
    get post_url(post)

    assert_response :success
    assert_includes response.body, 'type="application/ld+json"'
  end
end
