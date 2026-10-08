# frozen_string_literal: true

require "test_helper"

class CommunityBansControllerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @owner = User.strict_loading(false).create!(
      email_address: "cbc_owner@brgen.no", password: "password123", username: "cbc_owner", guest: false
    )
    @mod = User.strict_loading(false).create!(
      email_address: "cbc_mod@brgen.no", password: "password123", username: "cbc_mod", guest: false
    )
    @member = User.strict_loading(false).create!(
      email_address: "cbc_member@brgen.no", password: "password123", username: "cbc_member", guest: false
    )
    @nuisance = User.strict_loading(false).create!(
      email_address: "cbc_nuisance@brgen.no", password: "password123", username: "cbc_nuisance", guest: false
    )
    @community = Community.create!(name: "Bannby #{SecureRandom.hex(3)}", user: @owner)
    @community.community_memberships.create!(user: @owner, role: "owner")
    @community.community_memberships.create!(user: @mod, role: "moderator")
    @community.community_memberships.create!(user: @member, role: "member")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "a moderator bans, and the person can no longer post there" do
    sign_in_as(@mod)

    assert_difference -> { CommunityBan.count }, 1 do
      post community_bans_path(@community, user_id: @nuisance.id, reason: "Spam")
    end
    refute @community.reload.postable_by?(@nuisance)
  end

  test "days makes it temporary, and no days makes it permanent" do
    sign_in_as(@mod)

    post community_bans_path(@community, user_id: @nuisance.id, days: 3)
    ban = CommunityBan.last
    assert_in_delta 3.days.from_now.to_i, ban.expires_at.to_i, 60

    ban.destroy
    post community_bans_path(@community, user_id: @nuisance.id)
    assert CommunityBan.last.permanent?
  end

  test "an ordinary member cannot ban anyone" do
    sign_in_as(@member)

    assert_no_difference -> { CommunityBan.count } do
      post community_bans_path(@community, user_id: @nuisance.id)
    end
    assert_redirected_to community_path(@community)
  end

  # A mod team that cannot undo each other's mistakes escalates every
  # disagreement to the owner.
  test "any moderator can lift any ban" do
    ban = CommunityBan.create!(community: @community, user: @nuisance, banned_by: @owner)
    sign_in_as(@mod)

    assert_difference -> { CommunityBan.count }, -1 do
      delete community_ban_path(@community, ban)
    end
    assert @community.reload.postable_by?(@nuisance)
  end

  test "the mod queue offers a ban for the reported author, not the reporter" do
    reported_post = Post.create!(user: @nuisance, title: "Spam #{SecureRandom.hex(3)}", community: @community)
    ModerationWorkflow.report!(reporter: @member, target: reported_post, reason: "spam")
    sign_in_as(@mod)

    get community_moderation_index_path(@community)
    assert_response :success
    assert_match community_bans_path(@community, user_id: @nuisance.id), response.body
    refute_match community_bans_path(@community, user_id: @member.id), response.body
  end

  test "banning someone who does not exist says so rather than 500ing" do
    sign_in_as(@mod)

    assert_no_difference -> { CommunityBan.count } do
      post community_bans_path(@community, user_id: 0)
    end
    assert_response :redirect
  end
end
