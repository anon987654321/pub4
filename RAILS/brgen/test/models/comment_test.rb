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
test "a reply names a parent on its own thread, never another post's" do
  post, comment = build_post_with_comment
  other_post, other_comment = build_post_with_comment

  assert Comment.new(user_id: comment.user_id, commentable: post, content: "svar", parent_id: comment.id).valid?
  stray = Comment.new(user_id: comment.user_id, commentable: post, content: "svar", parent_id: other_comment.id)
  refute stray.valid?
  assert_includes stray.errors[:parent_id], I18n.t("errors.messages.invalid")
  refute_nil other_post
end

end
