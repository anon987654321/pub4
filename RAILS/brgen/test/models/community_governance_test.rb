# frozen_string_literal: true

require "test_helper"

# Community was eight columns with no moderators, rules, privacy or flair, and
# ModerationReport/ModerationFlag/TrustScore are global behind a single
# BRGEN_ADMIN_EMAIL — so there was no mod team per community and no queue per
# community. A community that cannot be moderated by its own members is a
# category page, not a subreddit.
class CommunityGovernanceTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(
      email_address: "cg_owner@brgen.no", password: "password123", username: "cg_owner", city: @city
    )
    @mod = User.strict_loading(false).create!(
      email_address: "cg_mod@brgen.no", password: "password123", username: "cg_mod", city: @city
    )
    @member = User.strict_loading(false).create!(
      email_address: "cg_member@brgen.no", password: "password123", username: "cg_member", city: @city
    )
    @outsider = User.strict_loading(false).create!(
      email_address: "cg_out@brgen.no", password: "password123", username: "cg_out", city: @city
    )
    ActsAsTenant.current_tenant = @city
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def community(privacy: "public", **attrs)
    c = Community.create!({ name: "Bergen #{SecureRandom.hex(3)}", user: @owner, privacy: privacy }.merge(attrs))
    c.community_memberships.create!(user: @owner, role: "owner")
    c
  end

  test "roles separate member, moderator and owner" do
    c = community
    c.community_memberships.create!(user: @mod, role: "moderator")
    c.community_memberships.create!(user: @member, role: "member")

    assert c.owner?(@owner)
    assert c.moderator?(@owner), "an owner moderates too"
    assert c.moderator?(@mod)
    refute c.owner?(@mod)
    refute c.moderator?(@member)
    refute c.member?(@outsider)
  end

  # Nothing else in the app creates an owner, so losing the last one is not a
  # state to recover from later — it is one to refuse now.
  test "the last owner cannot be demoted" do
    c = community
    membership = c.community_memberships.find_by(user_id: @owner.id)

    refute membership.update(role: "member")
    assert membership.errors.of_kind?(:role, :last_owner)

    c.community_memberships.create!(user: @mod, role: "owner")
    assert membership.reload.update(role: "member"), "a second owner makes the first demotable"
  end

  # Reading and posting are separate questions. Restricted is the interesting
  # one: the whole city reads it, only members post.
  test "privacy separates reading from posting" do
    open_c = community(privacy: "public")
    restricted = community(privacy: "restricted")
    private_c = community(privacy: "private")
    restricted.community_memberships.create!(user: @member, role: "member")
    private_c.community_memberships.create!(user: @member, role: "member")

    assert open_c.readable_by?(nil)
    assert open_c.postable_by?(@outsider)

    assert restricted.readable_by?(@outsider), "restricted is readable by the whole city"
    refute restricted.postable_by?(@outsider)
    assert restricted.postable_by?(@member)

    refute private_c.readable_by?(@outsider)
    assert private_c.readable_by?(@member)
  end

  test "a private community is not listed to people who are not in it" do
    hidden = community(privacy: "private")
    hidden.community_memberships.create!(user: @member, role: "member")

    refute_includes Community.visible_to(@outsider).map(&:id), hidden.id
    refute_includes Community.visible_to(nil).map(&:id), hidden.id
    assert_includes Community.visible_to(@member).map(&:id), hidden.id
  end

  test "an archived community takes no more posts" do
    c = community
    c.update!(archived_at: Time.current)

    refute c.postable_by?(@owner)
    refute_includes Community.popular.map(&:id), c.id
  end

  test "rules and flair are one per line, blank lines dropped" do
    c = community(rules: "Vaer snill\n\n  Ingen spam  \n", flairs: "Nyhet\nSpørsmål\n\n")

    assert_equal [ "Vaer snill", "Ingen spam" ], c.rule_list
    assert_equal [ "Nyhet", "Spørsmål" ], c.flair_options
  end

  test "members_count is a counter cache that tracks joins and leaves" do
    c = community
    assert_equal 1, c.reload.members_count, "the owner is a member"

    membership = c.community_memberships.create!(user: @member, role: "member")
    assert_equal 2, c.reload.members_count

    membership.destroy
    assert_equal 1, c.reload.members_count
  end

  # ModerationReport is polymorphic and has no community_id, so the queue is
  # derived rather than denormalised onto a column that would need backfilling.
  test "the queue holds reports against this community's posts, and no others" do
    mine = community
    theirs = community

    my_post = Post.create!(user: @member, title: "Her #{SecureRandom.hex(3)}", community: mine)
    their_post = Post.create!(user: @member, title: "Der #{SecureRandom.hex(3)}", community: theirs)

    ModerationWorkflow.report!(reporter: @outsider, target: my_post, reason: "spam")
    ModerationWorkflow.report!(reporter: @outsider, target: their_post, reason: "spam")

    queue = mine.moderation_queue.to_a
    assert_equal 1, queue.size
    assert_equal my_post.id, queue.first.reportable_id
  end

  test "the queue also holds reports against comments on this community's posts" do
    c = community
    post = Post.create!(user: @member, title: "Med kommentar #{SecureRandom.hex(3)}", community: c)
    comment = Comment.create!(user: @member, commentable: post, content: "noe")

    ModerationWorkflow.report!(reporter: @outsider, target: comment, reason: "abuse")

    assert_equal 1, c.moderation_queue.count
  end
end
