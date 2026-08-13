# frozen_string_literal: true

require "test_helper"

# A mod queue that can resolve a report but cannot stop the person who caused it
# is half a tool: resolving takes the content down, and the same account posts
# the same thing a minute later.
class CommunityBanTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @owner = User.strict_loading(false).create!(
      email_address: "cb_owner@brgen.no", password: "password123", username: "cb_owner", city: @city
    )
    @mod = User.strict_loading(false).create!(
      email_address: "cb_mod@brgen.no", password: "password123", username: "cb_mod", city: @city
    )
    @nuisance = User.strict_loading(false).create!(
      email_address: "cb_nuisance@brgen.no", password: "password123", username: "cb_nuisance", city: @city
    )
    @community = Community.create!(name: "Bannby #{SecureRandom.hex(3)}", user: @owner)
    @community.community_memberships.create!(user: @owner, role: "owner")
    @community.community_memberships.create!(user: @mod, role: "moderator")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def ban!(user: @nuisance, **attrs)
    CommunityBan.create!({ community: @community, user: user, banned_by: @mod }.merge(attrs))
  end

  # The whole point: a public community takes posts from anyone, which is what
  # made the queue unable to stop a repeat offender.
  test "a ban stops posting in a public community" do
    assert_equal "public", @community.privacy
    assert @community.postable_by?(@nuisance)

    ban!
    refute @community.postable_by?(@nuisance)
    assert @community.banned?(@nuisance)
  end

  # And the person to ban usually has no membership row, so a flag on
  # community_memberships would have had to invent one — making them a member
  # and bumping members_count in the act of banning them.
  test "banning someone who never joined does not make them a member" do
    assert_no_difference -> { @community.reload.members_count } do
      ban!
    end
    refute @community.member?(@nuisance)
  end

  test "a ban is scoped to its community and nowhere else" do
    other = Community.create!(name: "Annet #{SecureRandom.hex(3)}", user: @owner)
    other.community_memberships.create!(user: @owner, role: "owner")
    ban!

    refute @community.postable_by?(@nuisance)
    assert other.postable_by?(@nuisance), "one community's moderator must not silence someone everywhere"
  end

  test "a temporary ban lapses on its own" do
    ban = ban!(expires_at: 1.day.from_now)
    assert @community.banned?(@nuisance)
    refute ban.permanent?

    ban.update_columns(expires_at: 1.minute.ago)
    refute @community.reload.banned?(@nuisance)
    assert ban.reload.expired?
  end

  test "a permanent ban is the one with no end" do
    ban = ban!
    assert ban.permanent?
    assert_nil ban.expires_at
  end

  # A moderator banning another moderator is a fight the app should not settle.
  test "a moderator cannot be banned without being demoted first" do
    attempt = CommunityBan.new(community: @community, user: @mod, banned_by: @owner)
    refute attempt.valid?
    assert attempt.errors.of_kind?(:user, :is_a_moderator)

    @community.community_memberships.find_by(user_id: @mod.id).update!(role: "member")
    assert CommunityBan.new(community: @community, user: @mod, banned_by: @owner).valid?
  end

  test "the owner cannot be banned out of their own community" do
    refute CommunityBan.new(community: @community, user: @owner, banned_by: @mod).valid?
  end

  test "one ban per person per community" do
    ban!
    refute CommunityBan.new(community: @community, user: @nuisance, banned_by: @mod).valid?
  end

  # A ban nobody is told about reads as the site being broken — the person keeps
  # writing posts that vanish.
  test "the banned person is told, with the reason" do
    assert_difference -> { @nuisance.notifications.count }, 1 do
      ban!(reason: "Gjentatt spam")
    end
    notification = @nuisance.notifications.last
    assert_match @community.name, notification.title
    assert_match "Gjentatt spam", notification.body
    assert_equal "alert", notification.kind
  end

  test "lifting a ban restores posting" do
    ban = ban!
    refute @community.postable_by?(@nuisance)

    ban.destroy
    assert @community.reload.postable_by?(@nuisance)
  end
end
