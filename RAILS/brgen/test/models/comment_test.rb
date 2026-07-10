# frozen_string_literal: true

require "test_helper"

class CommentTest < ActiveSupport::TestCase
  def build_post_with_comment
    user = User.create!(email_address: "comment-test-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    post = Post.create!(user:, title: "Regression fixture", content: "body")
    comment = Comment.create!(user:, commentable: post, content: "first")
    [ post, comment ]
  end

  test "best scope orders by vote sum without raising a dangerous-query error" do
    _post, comment = build_post_with_comment
    assert_nothing_raised { Comment.where(id: comment.id).best.to_a }
  end

  test "controversial scope groups and orders without raising a dangerous-query error" do
    _post, comment = build_post_with_comment
    assert_nothing_raised { Comment.where(id: comment.id).controversial.to_a }
  end
end
