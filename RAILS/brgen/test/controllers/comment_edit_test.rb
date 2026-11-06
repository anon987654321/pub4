# frozen_string_literal: true

require "test_helper"

# A comment could only be deleted, never corrected. Its author may rewrite it
# for Comment::EDIT_WINDOW, as messages allow, and the thread marks it edited.
class CommentEditTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    host! "brgen.no"

    @author = member("edit-author")
    @other = member("edit-other")
    @post = Post.create!(user: @author, city: @city, title: "Tråd", content: "…")
    @comment = Comment.create!(user: @author, commentable: @post, content: "<p>skrivefeil</p>")
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

  test "the author edits inside the window and the thread marks it edited" do
    sign_in_as(@author)
    get post_path(@post)
    assert_select "#comment_#{@comment.id} a.comment-edit[href=?]", edit_comment_path(@comment)

    get edit_comment_path(@comment)
    assert_response :success
    assert_select "turbo-frame#comment_#{@comment.id} form[action=?]", comment_path(@comment)

    patch comment_path(@comment), params: { comment: { content: "<p>rettet</p>" } }, as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action='replace'][target='comment_#{@comment.id}']"
    assert_equal "<p>rettet</p>", @comment.reload.content
    assert @comment.edited_at.present?

    get post_path(@post)
    assert_select "#comment_#{@comment.id} .comment-edited", text: "endret"
  end

  test "an unchanged comment carries no edited mark" do
    get post_path(@post)
    assert_select "#comment_#{@comment.id} .comment-edited", 0
  end

  test "someone else cannot edit it" do
    sign_in_as(@other)
    get post_path(@post)
    assert_select "#comment_#{@comment.id} a.comment-edit", 0

    patch comment_path(@comment), params: { comment: { content: "<p>kapret</p>" } }, as: :turbo_stream
    assert_response :forbidden
    assert_equal "<p>skrivefeil</p>", @comment.reload.content
  end

  test "the window closes after Comment::EDIT_WINDOW" do
    @comment.update_columns(created_at: (Comment::EDIT_WINDOW + 1.minute).ago)
    sign_in_as(@author)

    get post_path(@post)
    assert_select "#comment_#{@comment.id} a.comment-edit", 0
    patch comment_path(@comment), params: { comment: { content: "<p>for sent</p>" } }, as: :turbo_stream
    assert_response :forbidden
  end
end
