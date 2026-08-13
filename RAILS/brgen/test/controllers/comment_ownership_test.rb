# frozen_string_literal: true

require "test_helper"

# comments#destroy guards by ownership, not by a before_action:
#
#   @comment.destroy if @comment.user == Current.user
#
# Same shape as blocks#destroy, on the highest-traffic destructive path in the
# app. Nothing tested it. The failure mode is quiet in both directions — drop the
# `if` and anyone deletes anything; the response is a redirect either way, so a
# smoke test that only checks the status code passes while the guard is gone.
#
# The soft-guest case is the one worth stating. This app gives anonymous visitors
# a real Current.user (Craigslist-style, no signup), so "is there a current user"
# is never the question. The question is only ever whether it is *this* one.
class CommentOwnershipTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def user(prefix)
    User.strict_loading(false).create!(
      email_address: "#{prefix}-#{SecureRandom.hex(4)}@brgen.no",
      password: "password123", city: @city,
    )
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  def a_post(author)
    community = Community.create!(name: "C #{SecureRandom.hex(3)}", slug: "c-#{SecureRandom.hex(4)}")
    Post.create!(user: author, community:, title: "Thread", content: "…")
  end

  test "the author can delete their own comment" do
    ActsAsTenant.with_tenant(@city) do
      author = user("comment-author")
      post_record = a_post(author)
      comment = Comment.create!(user: author, commentable: post_record, content: "mine")

      sign_in(author)

      assert_difference "Comment.count", -1 do
        delete comment_path(comment)
      end
    end
  end

  test "a signed-in stranger cannot delete someone else's comment" do
    ActsAsTenant.with_tenant(@city) do
      author = user("owner")
      stranger = user("stranger")
      post_record = a_post(author)
      comment = Comment.create!(user: author, commentable: post_record, content: "not yours")

      sign_in(stranger)

      assert_no_difference "Comment.count" do
        delete comment_path(comment)
      end
      assert Comment.exists?(comment.id), "a comment must only be deletable by its author"
    end
  end

  # A soft guest has a Current.user, so the ownership check is the whole guard.
  test "an anonymous visitor cannot delete a comment" do
    ActsAsTenant.with_tenant(@city) do
      author = user("guest-target")
      post_record = a_post(author)
      comment = Comment.create!(user: author, commentable: post_record, content: "still not yours")

      assert_no_difference "Comment.count" do
        delete comment_path(comment)
      end
      assert Comment.exists?(comment.id)
    end
  end

  # Every test above deletes by calling comment_path directly, so none of them
  # ever rendered the button a person would have to click to get there. That was
  # the blind spot: shared/comments/_comment builds the button's target from
  # comment_destroy_arg, which returns [commentable, comment] whenever the parent
  # is persisted — and there is no post_comment_path. brgen's comment routes are
  # `shallow: true`, so :destroy is a member action and lives at /comments/:id;
  # only :create is nested. The button therefore raised NoMethodError, and it
  # renders only when comment.user == Current.user, so it took signing in and
  # looking at your own comment. Deleting worked; the page offering it did not.
  test "a thread renders for the author of a comment in it" do
    ActsAsTenant.with_tenant(@city) do
      author = user("render-author")
      post_record = a_post(author)
      Comment.create!(user: author, commentable: post_record, content: "mine to delete")

      sign_in(author)
      get post_path(post_record)

      assert_response :success
      # Two arguments only: assert_select's third is an equality/count comparison,
      # not a failure message, and passing a sentence there asserts the element's
      # text equals that sentence.
      assert_select "form[action=?]", comment_path(Comment.last)
    end
  end

  # The post's author is not the comment's author. Owning the thread does not
  # confer the right to delete replies in it — if that is ever wanted it should
  # be an explicit moderation path, not a side effect of a widened check.
  test "the post author cannot delete a reply left on their post" do
    ActsAsTenant.with_tenant(@city) do
      thread_owner = user("thread-owner")
      commenter = user("commenter")
      post_record = a_post(thread_owner)
      comment = Comment.create!(user: commenter, commentable: post_record, content: "a reply")

      sign_in(thread_owner)

      assert_no_difference "Comment.count" do
        delete comment_path(comment)
      end
    end
  end
end
