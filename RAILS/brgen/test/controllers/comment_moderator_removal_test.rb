# frozen_string_literal: true

require "test_helper"

# A community's moderators could only work reports from the moderation queue;
# a comment someone had not reported stayed up. The comment now offers them
# its removal, recorded as a resolved report in that queue.
class CommentModeratorRemovalTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    host! "brgen.no"

    @owner = member("mod-owner")
    @moderator = member("mod-mod")
    @writer = member("mod-writer")
    @bystander = member("mod-bystander")
    @community = Community.create!(name: "Fjell #{SecureRandom.hex(3)}", user: @owner, city: @city)
    CommunityMembership.create!(community: @community, user: @moderator, role: "moderator")

    @post = Post.create!(user: @owner, city: @city, community: @community, title: "Tur", content: "…")
    @comment = Comment.create!(user: @writer, commentable: @post, content: "<p>stygt</p>")
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

  test "a moderator sees Remove on the comment and removing it takes it down" do
    sign_in_as(@moderator)
    get post_path(@post)
    assert_select "#comment_#{@comment.id} form[action=?]", remove_comment_path(@comment)

    patch remove_comment_path(@comment), as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action='remove'][target='comment_#{@comment.id}']"
    @comment.reload
    assert @comment.removed_at.present?
    report = ModerationReport.find_by!(reportable: @comment)
    assert_equal "resolved", report.status
    assert_equal @moderator.id, report.user_id
    assert_includes @community.moderation_queue, report
  end

  test "the community owner may remove too" do
    sign_in_as(@owner)
    patch remove_comment_path(@comment), as: :turbo_stream
    @comment.reload
    assert @comment.removed_at.present?
  end

  test "anyone else is refused and sees no Remove" do
    sign_in_as(@bystander)
    get post_path(@post)
    assert_select "#comment_#{@comment.id} form[action=?]", remove_comment_path(@comment), 0

    patch remove_comment_path(@comment), as: :turbo_stream
    assert_response :forbidden
    assert_nil @comment.reload.removed_at
  end

  test "a comment on a post outside any community offers no Remove" do
    loose = Post.create!(user: @owner, city: @city, title: "Løs", content: "…")
    comment = Comment.create!(user: @writer, commentable: loose, content: "<p>hei</p>")
    sign_in_as(@moderator)

    get post_path(loose)
    assert_select "#comment_#{comment.id} form[action=?]", remove_comment_path(comment), 0
    patch remove_comment_path(comment), as: :turbo_stream
    assert_response :forbidden
  end
end
