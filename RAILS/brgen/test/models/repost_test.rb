# frozen_string_literal: true

require "test_helper"

# The repost button rendered on every feed card for months with no route, model,
# controller or column behind it — and for part of that time it carried
# data-controller="action" with no URL, so a press added the active class, sent
# nothing, and told the user the repost had landed until the next render.
class RepostTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @author = User.strict_loading(false).create!(
      email_address: "rp_author@brgen.no", password: "password123", username: "rp_author", city: @city
    )
    @booster = User.strict_loading(false).create!(
      email_address: "rp_booster@brgen.no", password: "password123", username: "rp_booster", city: @city
    )
    @follower = User.strict_loading(false).create!(
      email_address: "rp_follower@brgen.no", password: "password123", username: "rp_follower", city: @city
    )
    ActsAsTenant.current_tenant = @city
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def post_by(user, title:)
    Post.create!(user: user, title: title, content: "Noe skjer på Bryggen")
  end

  test "reposting maintains the counter cache" do
    post = post_by(@author, title: "Sol på Fløyen #{SecureRandom.hex(3)}")

    assert_difference -> { post.reload.reposts_count }, 1 do
      Repost.create!(user: @booster, post: post)
    end
    assert post.reload.reposted_by?(@booster)
  end

  test "the same user cannot repost a post twice" do
    post = post_by(@author, title: "Regn i Bergen #{SecureRandom.hex(3)}")
    Repost.create!(user: @booster, post: post)

    duplicate = Repost.new(user: @booster, post: post)
    refute duplicate.valid?, "a second repost must not create a second row"
    assert_equal 1, post.reload.reposts_count
  end

  test "undoing a repost gives the count back" do
    post = post_by(@author, title: "Bybanen #{SecureRandom.hex(3)}")
    repost = Repost.create!(user: @booster, post: post)

    assert_difference -> { post.reload.reposts_count }, -1 do
      repost.destroy
    end
    refute post.reload.reposted_by?(@booster)
  end

  # The point of a repost is that it reaches the reposter's followers. One that
  # only showed on their own profile would be a bookmark with extra steps.
  test "a repost puts the post into the followers' timeline" do
    stranger = User.strict_loading(false).create!(
      email_address: "rp_stranger@brgen.no", password: "password123", username: "rp_stranger", city: @city
    )
    post = post_by(stranger, title: "Fra en fremmed #{SecureRandom.hex(3)}")

    @follower.follow!(@booster)
    refute_includes @follower.timeline_posts.map(&:id), post.id,
                    "guard: the follower does not follow the author"

    Repost.create!(user: @booster, post: post)

    assert_includes @follower.timeline_posts.map(&:id), post.id
  end

  test "a repost notifies the author, but reposting yourself does not" do
    post = post_by(@author, title: "Mitt eget #{SecureRandom.hex(3)}")

    assert_difference -> { @author.notifications.count }, 1 do
      Repost.create!(user: @booster, post: post)
    end

    own = post_by(@author, title: "Mitt andre #{SecureRandom.hex(3)}")
    assert_no_difference -> { @author.notifications.count } do
      Repost.create!(user: @author, post: own)
    end
  end

  test "destroying a post takes its reposts with it" do
    post = post_by(@author, title: "Slettes #{SecureRandom.hex(3)}")
    Repost.create!(user: @booster, post: post)

    assert_difference -> { Repost.count }, -1 do
      post.destroy
    end
  end
end
