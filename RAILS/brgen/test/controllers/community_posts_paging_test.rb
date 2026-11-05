# frozen_string_literal: true

require "test_helper"

# A community's posts page the way every other feed does: the infinite-scroll
# sentinel, backed by a reflex with the page's own scope, and the pager kept
# for a reader without JavaScript.
class CommunityPostsPagingTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    host! "brgen.no"
    @owner = User.strict_loading(false).create!(
      email_address: "cpp_#{SecureRandom.hex(3)}@brgen.no", password: "password123",
      username: "cpp_#{SecureRandom.hex(3)}", guest: false
    )
  end

  teardown do
    ActsAsTenant.current_tenant = nil
    Current.reset
  end

  def community(privacy: "public", posts: 0)
    club = Community.create!(name: "Lag #{SecureRandom.hex(3)}", user: @owner, privacy:)
    club.community_memberships.create!(user: @owner, role: "owner")
    posts.times do |n|
      Post.create!(user: @owner, city: @city, community: club, title: "Innlegg #{n}", content: "Tekst")
    end
    club
  end

  def reflex_for(club, page:)
    reflex = CommunityPostsInfiniteScrollReflex.allocate
    reflex.define_singleton_method(:element) do
      Struct.new(:dataset).new({ "community-id" => club.id.to_s, "next_page" => page.to_s })
    end
    reflex
  end

  test "a community with a second page carries the sentinel and a no-JS pager" do
    club = community(posts: 26)

    get community_path(club)

    assert_response :success
    assert_select "ul#community-posts > li", 25
    assert_select "#community-posts-sentinel[data-reflex='CommunityPostsInfiniteScrollReflex#load_more']" \
                  "[data-community-id='#{club.id}'][data-next-page='2']"
    assert_match %r{<noscript>.*page=2.*</noscript>}m, response.body
  end

  test "the reflex pages the community's own posts, in the page's order" do
    club = community(posts: 3)
    other = community(posts: 1)

    scope = reflex_for(club, page: 2).send(:scope)
    ids = scope.pluck(:id)
    expected = club.posts.hot

    assert_equal expected.pluck(:id), ids
    refute_includes ids, other.post_ids.first
  end

  test "the reflex shows nothing of a private community to an outsider" do
    club = community(privacy: "private", posts: 2)
    Current.user = nil

    assert_empty reflex_for(club, page: 2).send(:scope).to_a
  end
end
