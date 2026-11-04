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

  test "controversial leaves out comments a moderator removed" do
    post, comment = build_post_with_comment
    removed = Comment.create!(user_id: comment.user_id, commentable: post, content: "fjernet")
    [ comment, removed ].each do |target|
      [ 1, -1 ].each do |value|
        voter = User.create!(email_address: "voter-#{SecureRandom.hex(4)}@example.com", password: "password12345")
        Vote.create!(user: voter, votable: target, value:)
      end
    end
    removed.update_columns(removed_at: Time.current)

    ids = Comment.where(commentable: post).controversial.pluck(:id)
    assert_equal [ comment.id ], ids
  end

  test "long_thread_ids names the comments whose thread passes the threshold" do
    post, comment = build_post_with_comment
    quiet = Comment.create!(user_id: comment.user_id, commentable: post, content: "stille")
    reply = Comment.create!(user_id: comment.user_id, commentable: post, content: "svar", parent_id: comment.id)
    Comment::LONG_THREAD_THRESHOLD.times do |i|
      Comment.create!(user_id: comment.user_id, commentable: post, content: "svar #{i}", parent_id: reply.id)
    end

    ids = Comment.long_thread_ids("Post", post.id)
    assert_equal comment.long_thread?, ids.include?(comment.id)
    assert_includes ids, comment.id
    refute_includes ids, quiet.id
    assert_equal reply.long_thread?, ids.include?(reply.id)
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
