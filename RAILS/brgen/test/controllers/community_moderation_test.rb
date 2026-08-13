# frozen_string_literal: true

require "test_helper"

class CommunityModerationTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(
      email_address: "cm_owner@brgen.no", password: "password123", username: "cm_owner", guest: false
    )
    @mod = User.strict_loading(false).create!(
      email_address: "cm_mod@brgen.no", password: "password123", username: "cm_mod", guest: false
    )
    @member = User.strict_loading(false).create!(
      email_address: "cm_member@brgen.no", password: "password123", username: "cm_member", guest: false
    )
    ActsAsTenant.current_tenant = @city
    @community = Community.create!(name: "Modby #{SecureRandom.hex(3)}", user: @owner)
    @community.community_memberships.create!(user: @owner, role: "owner")
    @community.community_memberships.create!(user: @mod, role: "moderator")
    @community.community_memberships.create!(user: @member, role: "member")
    @post = Post.create!(user: @member, title: "Rapportert #{SecureRandom.hex(3)}", community: @community)
    @report = ModerationWorkflow.report!(reporter: @owner, target: @post, reason: "spam")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "a moderator sees and works their community's queue" do
    sign_in_as(@mod)

    get community_moderation_index_path(@community)
    assert_response :success
    assert_match @post.title, response.body

    patch community_moderation_path(@community, @report, status: "dismissed")
    assert_equal "dismissed", @report.reload.status
  end

  test "an ordinary member cannot reach the queue" do
    sign_in_as(@member)

    get community_moderation_index_path(@community)
    assert_redirected_to community_path(@community)

    patch community_moderation_path(@community, @report, status: "dismissed")
    assert_equal "open", @report.reload.status
  end

  # Only the owner appoints: if a moderator could change roles, one could demote
  # the person who made the community, and there is nothing above them to appeal
  # to.
  test "only the owner appoints moderators" do
    sign_in_as(@mod)
    post community_moderators_path(@community, user_id: @member.id)
    assert_equal "member", @community.community_memberships.find_by(user_id: @member.id).role

    sign_in_as(@owner)
    post community_moderators_path(@community, user_id: @member.id)
    assert_equal "moderator", @community.community_memberships.find_by(user_id: @member.id).role
  end

  test "appointing a moderator tells them" do
    sign_in_as(@owner)

    assert_difference -> { @member.notifications.count }, 1 do
      post community_moderators_path(@community, user_id: @member.id)
    end
  end

  test "appointing someone who is not a member is refused" do
    stranger = User.strict_loading(false).create!(
      email_address: "cm_stranger@brgen.no", password: "password123", username: "cm_stranger", guest: false
    )
    sign_in_as(@owner)

    post community_moderators_path(@community, user_id: stranger.id)
    assert_nil @community.community_memberships.find_by(user_id: stranger.id)
  end

  test "the last owner cannot be demoted through the UI either" do
    sign_in_as(@owner)
    owner_membership = @community.community_memberships.find_by(user_id: @owner.id)

    delete community_moderator_path(@community, owner_membership)
    assert_equal "owner", owner_membership.reload.role
  end

  # A hidden compose link is not a permission check.
  test "a restricted community refuses a non-member's post on submit" do
    @community.update!(privacy: "restricted")
    stranger = User.strict_loading(false).create!(
      email_address: "cm_nonmember@brgen.no", password: "password123", username: "cm_nonmember", guest: false
    )
    sign_in_as(stranger)

    assert_no_difference -> { Post.count } do
      post community_posts_path(@community), params: { post: { title: "Utenfra", content: "hei" } }
    end
  end

  test "a private community is not readable by an outsider" do
    @community.update!(privacy: "private")
    stranger = User.strict_loading(false).create!(
      email_address: "cm_private@brgen.no", password: "password123", username: "cm_private", guest: false
    )
    sign_in_as(stranger)

    get community_path(@community)
    assert_redirected_to communities_path
  end

  test "flair filters the community feed" do
    @community.update!(flairs: "Nyhet\nSpørsmål")
    tagged = Post.create!(user: @member, title: "Med flair #{SecureRandom.hex(3)}", community: @community, flair: "Nyhet")
    sign_in_as(@member)

    get community_path(@community, flair: "Nyhet")
    assert_response :success
    assert_match tagged.title, response.body
    refute_match @post.title, response.body
  end
end
