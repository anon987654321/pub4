# frozen_string_literal: true

require "test_helper"

# The privileged actions that previously left no trace.
#
# CommunityBan carries banned_by, reason and expires_at, so every fact about a
# ban lived on the row — and Communities::BansController#destroy deletes it. The
# existing "any moderator can lift any ban" test asserts the row count drops by
# one, which is exactly the behaviour that used to erase the evidence. These
# assert the record survives it.
class ModerationAuditTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @owner = create_person("mat_owner")
    @mod = create_person("mat_mod")
    @member = create_person("mat_member")
    @nuisance = create_person("mat_nuisance")
    @community = Community.create!(name: "Auditby #{SecureRandom.hex(3)}", user: @owner)
    @community.community_memberships.create!(user: @owner, role: "owner")
    @community.community_memberships.create!(user: @mod, role: "moderator")
    @community.community_memberships.create!(user: @member, role: "member")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_person(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123",
      username: "#{name}_#{SecureRandom.hex(2)}", guest: false
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "banning someone is recorded with who did it and to whom" do
    sign_in_as(@mod)

    assert_difference -> { Shared::AuditEvent.count }, 1 do
      post community_bans_path(@community, user_id: @nuisance.id, reason: "Spam")
    end

    event = Shared::AuditEvent.last
    assert_equal "community.ban.created", event.action
    assert_equal @mod.id, event.actor_id
    assert_equal @community.id, event.context_id
    assert_equal "Community", event.context_type
    assert_equal @nuisance.id, event.metadata["subject_id"]
    assert_equal "Spam", event.metadata["reason"]
  end

  # The reason this table exists. Lifting a ban destroys the only row that knew
  # who imposed it and why, so the audit record has to be written from values
  # read off the row *before* destroy — a bug here loses the facts silently,
  # because the redirect looks identical either way.
  test "lifting a ban preserves what the destroyed row knew" do
    ban = CommunityBan.create!(community: @community, user: @nuisance,
                               banned_by: @owner, reason: "Repeated spam")
    sign_in_as(@mod)

    delete community_ban_path(@community, ban)

    assert_nil CommunityBan.find_by(id: ban.id), "the ban row should be gone"
    event = Shared::AuditEvent.where(action: "community.ban.lifted").last
    assert event, "lifting a ban must be audited"
    assert_equal @mod.id, event.actor_id, "who lifted it"
    assert_equal @owner.id, event.metadata["banned_by_id"], "who had imposed it"
    assert_equal @nuisance.id, event.metadata["subject_id"], "who it was on"
    assert_equal "Repeated spam", event.metadata["reason"], "why"
  end

  test "role changes in both directions are recorded" do
    sign_in_as(@owner)

    post community_moderators_path(@community, user_id: @member.id)
    appointed = Shared::AuditEvent.where(action: "community.moderator.appointed").last
    assert appointed
    assert_equal @member.id, appointed.metadata["subject_id"]

    membership = @community.community_memberships.find_by(user_id: @member.id)
    delete community_moderator_path(@community, membership)
    removed = Shared::AuditEvent.where(action: "community.moderator.removed").last
    assert removed
    assert_equal @member.id, removed.metadata["subject_id"]
  end

  # A refused action is not an action. Auditing attempts is a different and much
  # noisier instrument, and the ordinary-member path already redirects away.
  test "a refused ban writes nothing" do
    sign_in_as(@member)

    assert_no_difference -> { Shared::AuditEvent.count } do
      post community_bans_path(@community, user_id: @nuisance.id)
    end
  end

  test "the log is append-only" do
    event = Shared::Audit.record!(action: "community.ban.created", actor: @mod,
                                  context: @community, metadata: { subject: "x" })
    assert event

    record = Shared::AuditEvent.last
    assert_raises(ActiveRecord::ReadOnlyRecord) { record.update!(action: "something.else") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { record.destroy }
  end

  # The read surface. A moderation log nobody can reach is a table, not a
  # feature — and the lifted ban is the entry that exists nowhere else.
  test "moderators read the log on the bans page" do
    ban = CommunityBan.create!(community: @community, user: @nuisance, banned_by: @owner)
    sign_in_as(@mod)
    delete community_ban_path(@community, ban)

    get community_bans_path(@community)
    assert_response :success
    assert_select "#moderation_log_heading"
    assert_select ".audit-list li", 1
    assert_match @nuisance.display_name, response.body
  end

  # One community's moderators must not be handed another's log. Same rule the
  # ban itself follows: a community-scoped power stays community-scoped.
  test "the log is scoped to its community" do
    other = Community.create!(name: "Elsewhere #{SecureRandom.hex(3)}", user: @owner)
    other.community_memberships.create!(user: @owner, role: "owner")
    Shared::Audit.record!(action: "community.ban.created", actor: @owner, context: other,
                          metadata: { subject: "someone_elsewhere" })

    sign_in_as(@mod)
    get community_bans_path(@community)
    assert_response :success
    refute_match "someone_elsewhere", response.body
  end
end
