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

  test "non-owner cannot update another user's post" do
    owner  = User.create!(email_address: "post-owner-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    other  = User.create!(email_address: "post-other-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    post   = Post.create!(user: owner, title: "Original", content: "body")

    host! "brgen.no"
    post session_url, params: { email_address: other.email_address, password: "password12345" }
    patch post_url(post), params: { post: { title: "Hijacked" } }

    assert_redirected_to post_url(post)
    assert_equal "Original", post.reload.title
  end

  test "non-owner cannot destroy another user's post" do
    owner  = User.create!(email_address: "post-owner2-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    other  = User.create!(email_address: "post-other2-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    post   = Post.create!(user: owner, title: "Original", content: "body")

    host! "brgen.no"
    post session_url, params: { email_address: other.email_address, password: "password12345" }
    assert_no_difference "Post.count" do
      delete post_url(post)
    end
  end
end
