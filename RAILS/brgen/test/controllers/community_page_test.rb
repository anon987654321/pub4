# frozen_string_literal: true

require "test_helper"

# What the community page offers and what joining says. A ban kept someone
# from posting but not from leaving and rejoining, the page offered a compose
# link to guests and banned users, and the counts and copy were English or
# counted removed posts.
class CommunityPageTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    host! "brgen.no"
    @owner = person("cpt_owner")
    @community = Community.create!(name: "Sideby #{SecureRandom.hex(3)}", user: @owner, flairs: "Spørsmål\nNyhet")
    @community.community_memberships.create!(user: @owner, role: "owner")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def person(prefix)
    User.strict_loading(false).create!(
      email_address: "#{prefix}_#{SecureRandom.hex(3)}@brgen.no", password: "password123",
      username: "#{prefix}_#{SecureRandom.hex(3)}", guest: false
    )
  end

  def sign_in_as(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "a banned user cannot rejoin the community" do
    banned = person("cpt_banned")
    CommunityBan.create!(community: @community, user: banned, banned_by: @owner, reason: "spam")
    sign_in_as(banned)

    post join_community_path(@community)

    refute @community.member?(banned)
    assert_equal I18n.t("community.join_banned", locale: :nb), flash[:alert]
  end

  test "joining and leaving answer in the visitor's language" do
    visitor = person("cpt_joiner")

    sign_in_as(visitor)

    post join_community_path(@community)
    assert_equal "Du er med.", flash[:notice]

    delete leave_community_path(@community)
    assert_equal "Du har forlatt fellesskapet.", flash[:notice]
  end

  test "a banned user on an empty community is offered no compose link" do
    banned = person("cpt_banned_reader")
    CommunityBan.create!(community: @community, user: banned, banned_by: @owner, reason: "spam")
    sign_in_as(banned)

    get community_path(@community)

    assert_response :success
    assert_select "a[href=?]", new_community_post_path(@community), count: 0
    assert_select "aside p", text: I18n.t("communities.no_description", locale: :nb)
    refute_includes response.body, "No description."
  end

  test "the post count leaves out removed posts and the chosen flair is current" do
    Post.create!(user: @owner, title: "kept", content: "…", community: @community, flair: "Nyhet")
    Post.create!(user: @owner, title: "gone", content: "…", community: @community, removed_at: Time.current)

    get community_path(@community, flair: "Nyhet")

    assert_select ".community-header p", text: /\A#{I18n.t("community.posts_count", count: 1, locale: :nb)}/
    assert_select "nav.chips a[aria-current='page']", count: 1, text: "Nyhet"
  end

  test "a shared community link previews with its description and banner" do
    @community.update!(description: "<p>Naboer som deler verktøy</p>")
    attach_pixel!(@community.banner, filename: "banner.png")

    get community_path(@community)

    assert_select "meta[name=description][content=?]", "Naboer som deler verktøy"
    assert_select "meta[property='og:image'][content*='banner.png']"
  end

  test "the header's post count is the pager's own count, not a second query" do
    Post.create!(user: @owner, title: "kept", content: "…", community: @community)
    counts = 0
    counter = ->(*, payload) { counts += 1 if payload[:sql].match?(/SELECT COUNT\(\*\) FROM "posts"/) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get community_path(@community) }

    assert_select ".community-header p", text: /\A#{I18n.t("community.posts_count", count: 1, locale: :nb)}/
    assert_equal 1, counts
  end
end
