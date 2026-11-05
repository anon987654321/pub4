# frozen_string_literal: true

require "test_helper"

# Deleting a comment others had answered took every reply with it
# (dependent: :destroy). It leaves a tombstone now; a leaf still goes outright.
class CommentTombstoneTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    host! "brgen.no"

    @author = member("tomb-author")
    @replier = member("tomb-replier")
    @post = Post.create!(user: @author, city: @city, title: "Tråd", content: "…")
    @root = Comment.create!(user: @author, commentable: @post, content: "hemmelig innhold")
    @reply = Comment.create!(user: @replier, commentable: @post, content: "et svar", parent_id: @root.id)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def member(prefix)
    User.strict_loading(false).create!(email_address: "#{prefix}-#{SecureRandom.hex(4)}@brgen.no",
                                       username: "#{prefix.tr("-", "_")}_#{SecureRandom.hex(3)}",
                                       password: "password123", guest: false, city: @city)
  end

  def sign_in_as(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "deleting a comment with replies keeps a tombstone and the replies" do
    sign_in_as(@author)

    assert_no_difference -> { Comment.count } do
      delete comment_path(@root), as: :turbo_stream
    end

    assert_response :success
    assert_select "turbo-stream[action='replace'][target='comment_#{@root.id}']"
    assert @root.reload.tombstoned?
    assert_equal "", @root.content
    assert Comment.exists?(@reply.id)

    get post_path(@post)
    assert_select "#comment_#{@root.id} .comment-deleted", text: "[slettet]"
    assert_select "#comment_#{@root.id} > article > header .comment-author", 0
    assert_select "#replies_comment_#{@root.id} #comment_#{@reply.id}"
    assert_no_match "hemmelig innhold", response.body
  end

  test "a comment nobody answered is deleted outright" do
    sign_in_as(@replier)

    assert_difference -> { Comment.count }, -1 do
      delete comment_path(@reply), as: :turbo_stream
    end
    assert_select "turbo-stream[action='remove'][target='comment_#{@reply.id}']"
  end

  test "the last reply going takes its tombstone with it" do
    sign_in_as(@author)
    delete comment_path(@root), as: :turbo_stream
    delete session_path
    sign_in_as(@replier)

    delete comment_path(@reply), as: :turbo_stream

    assert_not Comment.exists?(@reply.id)
    assert_not Comment.exists?(@root.id)
  end

  test "a tombstone cannot be deleted again by its author" do
    sign_in_as(@author)
    delete comment_path(@root), as: :turbo_stream
    delete comment_path(@root), as: :turbo_stream

    assert_response :forbidden
    assert Comment.exists?(@root.id)
  end
end
