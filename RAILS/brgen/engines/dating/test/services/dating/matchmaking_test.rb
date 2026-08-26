# frozen_string_literal: true

require "test_helper"

# The bug these pin: a match is symmetric and the unique index on
# [initiator_id, receiver_id] is not, so the direction the finder looks in
# decides whether it finds anything. Running matchmaking from *both* sides of a
# mutual like is the case that produced two rows for one pair.
class Dating::MatchmakingTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @kari = user("mm_kari@brgen.no")
    @jonas = user("mm_jonas@brgen.no")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "running from both sides of a mutual like leaves one match" do
    ActsAsTenant.with_tenant(@city) do
      profile(@kari)
      profile(@jonas)
      like(@kari, @jonas)
      like(@jonas, @kari)

      Dating::Matchmaking.call(@kari)
      Dating::Matchmaking.call(@jonas)

      assert_equal 1, matches_between(@kari, @jonas).count,
                   "the second side found no (jonas, kari) row and minted one, so the pair matched twice"
    end
  end

  test "the surviving match is the one Match.between already found" do
    ActsAsTenant.with_tenant(@city) do
      profile(@kari)
      profile(@jonas)
      like(@kari, @jonas)
      like(@jonas, @kari)

      first = Dating::Matchmaking.call(@kari) && Dating::Match.between(@kari, @jonas)
      Dating::Matchmaking.call(@jonas)

      assert_equal first.id, Dating::Match.between(@jonas, @kari).id
    end
  end

  # A second announce_match is what the duplicate row actually cost a user: two
  # notifications and two overlays for one match.
  test "the second run notifies nobody a second time" do
    ActsAsTenant.with_tenant(@city) do
      profile(@kari)
      profile(@jonas)
      like(@kari, @jonas)
      like(@jonas, @kari)

      Dating::Matchmaking.call(@kari)
      before = Notification.where(kind: "match").count
      Dating::Matchmaking.call(@jonas)

      assert_equal before, Notification.where(kind: "match").count
    end
  end

  test "an unmatched pair is re-matched rather than duplicated" do
    ActsAsTenant.with_tenant(@city) do
      profile(@kari)
      profile(@jonas)
      like(@kari, @jonas)
      like(@jonas, @kari)
      Dating::Matchmaking.call(@kari)

      match = Dating::Match.between(@kari, @jonas)
      match.update!(status: "unmatched")
      Dating::Matchmaking.call(@jonas)

      assert_equal 1, matches_between(@kari, @jonas).count
      assert_equal "matched", match.reload.status
    end
  end

  test "no mutual like creates no match" do
    ActsAsTenant.with_tenant(@city) do
      profile(@kari)
      profile(@jonas)
      like(@kari, @jonas)

      Dating::Matchmaking.call(@kari)

      assert_equal 0, matches_between(@kari, @jonas).count
    end
  end

  private

  def user(email)
    User.strict_loading(false).create!(email_address: email, password: "password123", city: @city)
  end

  # visible: false deliberately — photos_present_when_visible would demand an
  # attachment, and nothing here reads the discover deck. create_mutual_matches
  # only needs the profile to exist.
  def profile(owner)
    Dating::Profile.create!(user: owner, age: 30, bio: "seed", visible: false,
                            latitude: 60.39, longitude: 5.32)
  end

  def like(liker, likee)
    Dating::Like.create!(liker: liker, likee: likee)
  end

  def matches_between(one, two)
    Dating::Match.where(initiator_id: one.id, receiver_id: two.id)
                 .or(Dating::Match.where(initiator_id: two.id, receiver_id: one.id))
  end
end
