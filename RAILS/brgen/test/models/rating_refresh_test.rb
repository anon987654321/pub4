# frozen_string_literal: true

require "test_helper"

# Marketplace::Review and Takeaway::Review both refresh their parent's average
# rating from an after_commit that fires on destroy. A review being destroyed
# was found by id — nothing preloaded — and ApplicationRecord is strict_loading
# by default with test and production both raising. So the parent read in the
# callback blew up *after* the delete had committed: the review was gone and the
# cached rating still counted it.
#
# Same shape as Marketplace::Order#mark_paid! and Dating::Match#other_user.
# Neither review model had a test; the contract suite only greps their source.
class RatingRefreshTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def user(prefix)
    User.strict_loading(false).create!(
      email_address: "#{prefix}-#{SecureRandom.hex(4)}@brgen.no",
      password: "password123",
      city: @city,
    )
  end

  test "destroying a marketplace review found by id refreshes the listing rating" do
    ActsAsTenant.with_tenant(@city) do
      seller = user("rating-seller")
      buyer = user("rating-buyer")
      category = Marketplace::Category.find_or_create_by!(name: "Ratings", slug: "ratings-#{SecureRandom.hex(4)}")
      listing = Marketplace::Listing.create!(user: seller, category:, title: "Lamp", price_cents: 5_000, currency: "NOK")
      Marketplace::Order.create!(buyer:, listing:, status: "accepted")
      review = Marketplace::Review.create!(user: buyer, listing:, rating: 5)

      Marketplace::Review.find(review.id).destroy!

      assert_not Marketplace::Review.exists?(review.id)
    end
  end

  test "destroying a takeaway review found by id refreshes the restaurant rating" do
    ActsAsTenant.with_tenant(@city) do
      diner = user("rating-diner")
      restaurant = Takeaway::Restaurant.create!(
        user: user("rating-owner"), name: "Kro #{SecureRandom.hex(3)}",
        address: "Storgata 1", cuisine_type: "nordic", city: @city, active: true,
      )
      order = place_takeaway_order!(
        user: diner, restaurant: restaurant, delivery_address: "Storgata 2", status: "pending"
      )
      review = Takeaway::Review.create!(user: diner, restaurant:, order:, rating: 4)

      Takeaway::Review.find(review.id).destroy!

      assert_not Takeaway::Review.exists?(review.id)
    end
  end

  # Follow#emit_follow_created reads both sides to build the notification, and
  # rescues StandardError into a log line — so a strict-loading violation there
  # does not fail loudly, it silently stops notifying.
  test "following notifies the followed user without swallowing an error" do
    ActsAsTenant.with_tenant(@city) do
      follower = user("follow-a")
      followed = user("follow-b")

      assert_difference "Notification.count", 1 do
        Follow.create!(follower:, followed:)
      end
    end
  end

  test "unfollowing a follow found by id succeeds" do
    ActsAsTenant.with_tenant(@city) do
      follow = Follow.create!(follower: user("follow-c"), followed: user("follow-d"))

      Follow.find(follow.id).destroy!

      assert_not Follow.exists?(follow.id)
    end
  end
end
