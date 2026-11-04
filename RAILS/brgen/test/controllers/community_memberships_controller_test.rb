# frozen_string_literal: true

require "test_helper"

# Joining and leaving a community: who is let in, who is kept out, and the
# one leave that is refused.
class CommunityMembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    host! "brgen.no"
    @owner = person("cmc_owner")
    @visitor = person("cmc_visitor")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def person(prefix)
    User.strict_loading(false).create!(
      email_address: "#{prefix}_#{SecureRandom.hex(3)}@brgen.no", password: "password123",
      username: "#{prefix}_#{SecureRandom.hex(3)}", guest: false
    )
  end

  def community(privacy: "public")
    club = Community.create!(name: "Lag #{SecureRandom.hex(3)}", user: @owner, privacy:)
    club.community_memberships.create!(user: @owner, role: "owner")
    club
  end

  def sign_in_as(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "a member of the city joins a public community and leaves it again" do
    club = community
    sign_in_as(@visitor)

    post join_community_path(club)
    assert club.member?(@visitor)

    delete leave_community_path(club)
    refute club.member?(@visitor)
  end

  test "an outsider cannot join a private community" do
    club = community(privacy: "private")
    sign_in_as(@visitor)

    post join_community_path(club)

    assert_redirected_to communities_path
    refute club.member?(@visitor)
  end

  test "a banned user is refused at the door" do
    club = community
    CommunityBan.create!(community: club, user: @visitor, banned_by: @owner, reason: "spam")
    sign_in_as(@visitor)

    post join_community_path(club)

    refute club.member?(@visitor)
    assert_equal I18n.t("community.join_banned"), flash[:alert]
  end

  test "the last owner cannot leave the community without anyone to run it" do
    club = community
    sign_in_as(@owner)

    delete leave_community_path(club)

    assert club.member?(@owner)
    assert_equal I18n.t("flash.community.last_owner_leaving"), flash[:alert]
  end
end
