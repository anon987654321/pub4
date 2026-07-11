# frozen_string_literal: true

require "test_helper"

class PostsControllerAnonymousTest < ActionDispatch::IntegrationTest
  def test_guest_can_post_anonymously_on_frontpage
    get root_url
    assert_response :success
    assert_includes response.body, "amber-compose-box"

    assert_difference -> { Post.count }, 1 do
      post posts_url, params: { post: { body: "Loving this linen capsule #ootd", anonymous: true } }
    end

    assert_redirected_to root_url
    post = Post.order(:id).last
    assert post.anonymous?
    assert post.user.guest?
    assert_equal "Loving this linen capsule #ootd", post.body
  end
end