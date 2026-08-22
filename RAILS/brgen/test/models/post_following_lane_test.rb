# frozen_string_literal: true

require "test_helper"

# The follow button wrote a row nothing read: Follow existed, profiles carried
# the button, and the feed had no lane that consulted the graph. This pins the
# lane and the ONE resolver both the controller and the infinite-scroll reflex
# now share — twin case statements over the same param is how a lane pages
# differently than it renders.
class PostFollowingLaneTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @reader = make_user("reader")
    @followed = make_user("followed")
    @stranger = make_user("stranger")
    Follow.create!(follower: @reader, followed: @followed)
  end
  teardown { ActsAsTenant.current_tenant = nil }

  def make_user(tag)
    User.create!(email_address: "#{tag}-#{SecureRandom.hex(4)}@brgen.no",
                 password: SecureRandom.hex(16), username: "#{tag}_#{SecureRandom.hex(3)}", city: @city)
  end

  def make_post(user, title)
    Post.create!(title: title, content: "innhold om #{title} i nabolaget", user: user)
  end

  test "the following lane shows the graph and only the graph, newest first" do
    older = make_post(@followed, "eldre")
    newer = make_post(@followed, "nyere")
    noise = make_post(@stranger, "fremmed")

    ids = Post.followed_by(@reader).pluck(:id)
    assert_equal [newer.id, older.id], ids.first(2), "chronological, newest first — ranking is the fenced horizon item"
    assert_not_includes ids, noise.id, "a stranger's post must never reach the following lane"
  end

  test "the resolver routes following to the graph for a viewer and to hot for nobody" do
    mine = make_post(@followed, "til leseren")
    assert_includes Post.sorted_lane("following", viewer: @reader).pluck(:id), mine.id
    # Signed out, the crafted URL falls back to hot rather than raising.
    assert_equal Post.hot.to_sql, Post.sorted_lane("following", viewer: nil).to_sql
    assert_equal Post.fresh.to_sql, Post.sorted_lane("fresh").to_sql
    assert_equal Post.hot.to_sql, Post.sorted_lane(nil).to_sql
  end

  test "unfollowing empties the lane" do
    make_post(@followed, "forsvinner")
    Follow.find_by!(follower: @reader, followed: @followed).destroy
    assert_empty Post.followed_by(@reader).pluck(:id)
  end
end
