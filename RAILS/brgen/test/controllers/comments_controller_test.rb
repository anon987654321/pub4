# frozen_string_literal: true

require "test_helper"

# Posting a comment worked. Displaying it on the same page did not:
# create.turbo_stream always appended to #comments, so the empty-state li
# stayed after the first comment and a reply landed as a sibling of its
# parent rather than inside it. The stream is the thing a person sees.
class CommentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def user(prefix)
    User.strict_loading(false).create!(
      email_address: "#{prefix}-#{SecureRandom.hex(4)}@brgen.no",
      username: "#{prefix.tr("-", "_")}_#{SecureRandom.hex(3)}",
      password: "password123", city: @city,
    )
  end

  def a_post(author)
    Post.create!(user: author, title: "Thread", content: "…", city: @city)
  end

  test "a guest can post a comment and the stream replaces the empty state" do
    ActsAsTenant.with_tenant(@city) do
      post_record = a_post(user("thread"))

      get post_path(post_record)
      assert_response :success
      assert_select "#comments_empty"

      assert_difference -> { Comment.count }, 1 do
        post post_comments_path(post_record),
             params: { comment: { content: "hello from a guest" } },
             as: :turbo_stream
      end

      assert_response :success
      assert_select "turbo-stream[action='remove'][target='comments_empty']"
      assert_select "turbo-stream[action='append'][target='comments']"
      assert_includes response.body, "hello from a guest"
      assert_select "turbo-stream[action='replace'][target='comment_form']"
    end
  end

  test "a departing comment author is rendered as anonymous" do
    author = user("departing-comment")
    post_record = a_post(author)
    comment = Comment.create!(user: author, commentable: post_record, content: "private author")
    author.update_columns(deleted_at: Time.current, deletion_scheduled_at: 7.days.from_now)

    get post_path(post_record)

    assert_response :success
    assert_select ".comment-author", text: "anon", count: 1
    refute_includes response.body, author.username
  end

  test "a reply streams into the parent thread, not the top of the list" do
    ActsAsTenant.with_tenant(@city) do
      author = user("parent-author")
      post_record = a_post(author)
      parent = Comment.create!(user: author, commentable: post_record, content: "root")

      get post_path(post_record)
      assert_response :success

      assert_difference -> { Comment.count }, 1 do
        post post_comments_path(post_record),
             params: { comment: { content: "nested reply" }, parent_id: parent.id },
             as: :turbo_stream
      end

      assert_response :success
      assert_select "turbo-stream[action='append'][target=?]", "replies_comment_#{parent.id}"
      assert_select "turbo-stream[action='append'][target='comments']", count: 0
      # The disclosure goes back closed, carrying a fresh reply form.
      assert_select "turbo-stream[action='replace'][target=?]", "reply_disclosure_comment_#{parent.id}"
      assert_select "details#reply_disclosure_comment_#{parent.id}:not([open]) form#reply_form_#{parent.id}"
      assert_includes response.body, "nested reply"
    end
  end

  test "an empty thread still offers the comment form to a guest" do
    ActsAsTenant.with_tenant(@city) do
      post_record = a_post(user("empty-thread"))

      get post_path(post_record)

      assert_response :success
      assert_select "form#comment_form"
      assert_select "#comments_empty"
    end
  end

  test "a stranger cannot summarize a private community comment" do
    owner = user("private-owner")
    outsider = user("private-outsider")
    community = Community.create!(name: "Private #{SecureRandom.hex(3)}", user: owner, city: @city, privacy: "private")
    post_record = Post.create!(user: owner, title: "secret", city: @city, community: community)
    comment = Comment.create!(user: owner, commentable: post_record, content: "private thread")

    post session_path, params: { email_address: outsider.email_address, password: "password123" }
    assert_response :redirect

    post generate_summary_comment_path(comment)

    assert_response :not_found
  end

  test "a failed reply re-renders its own reply form, not the root comment form" do
    ActsAsTenant.with_tenant(@city) do
      post_record = a_post(user("failed-reply"))
      parent = Comment.create!(user: post_record.user, commentable: post_record, content: "root")

      assert_no_difference -> { Comment.count } do
        post post_comments_path(post_record),
             params: { comment: { content: "" }, parent_id: parent.id },
             as: :turbo_stream
      end

      assert_select "turbo-stream[action='replace'][target=?]", "reply_form_#{parent.id}"
      assert_select "turbo-stream[action='replace'][target='comment_form']", count: 0
      assert_select "form#reply_form_#{parent.id} input[name='parent_id'][value=?]", parent.id.to_s
    end
  end

  test "a member banned from a community cannot comment on its posts" do
    owner = user("ban-owner")
    banned = user("ban-commenter")
    banned.update_columns(email_verified_at: Time.current)
    community = Community.create!(name: "Banned #{SecureRandom.hex(3)}", user: owner, city: @city, privacy: "public")
    post_record = Post.create!(user: owner, title: "open thread", city: @city, community:)
    CommunityBan.create!(community:, user: banned, banned_by: owner, reason: "spam")

    post session_path, params: { email_address: banned.email_address, password: "password123" }
    assert_no_difference -> { Comment.count } do
      post post_comments_path(post_record), params: { comment: { content: "still here" } }, as: :turbo_stream
    end
    assert_response :forbidden
  end

  test "a nested thread renders without a depth or long-thread query per row" do
    ActsAsTenant.with_tenant(@city) do
      author = user("deep-thread")
      post_record = a_post(author)
      parent = Comment.create!(user: author, commentable: post_record, content: "root")
      3.times do |i|
        parent = Comment.create!(user: author, commentable: post_record, content: "nivå #{i}", parent_id: parent.id)
      end

      per_row = []
      depth_sql = /SELECT "comments"\."parent_id" FROM/
      per_row_sql = Regexp.union(depth_sql, /SELECT COUNT\(\*\) FROM "comments" WHERE "comments"\."parent_id"/)
      counter = ->(*, payload) { per_row << payload[:sql] if payload[:sql].match?(per_row_sql) }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get post_path(post_record) }

      assert_response :success
      assert_select "article.comment[data-depth='3']"
      assert_empty per_row
    end
  end

  test "a comment names its author with a profile link, marks the post author, and carries a permalink" do
    ActsAsTenant.with_tenant(@city) do
      author = user("op-author")
      reader = user("op-reader")
      post_record = a_post(author)
      own = Comment.create!(user: author, commentable: post_record, content: "fra forfatteren")
      Comment.create!(user: reader, commentable: post_record, content: "fra en leser")

      get post_path(post_record)

      assert_select "a.comment-author[href=?]", user_path(author)
      assert_select "a.comment-author[href=?]", user_path(reader)
      assert_select ".comment-op", count: 1, text: I18n.t("comments.op_badge", locale: :nb)
      assert_select "a.comment-permalink[href=?] time", "#comment_#{own.id}"
    end
  end

  test "a comment posted to no parent is a 404, not a 500" do
    post comments_path, params: { comment: { content: "til ingen" } }
    assert_response :not_found
  end
end
