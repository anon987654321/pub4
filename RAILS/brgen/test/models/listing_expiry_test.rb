# frozen_string_literal: true

require "test_helper"

# Classifieds expire. Without it a marketplace fills with things sold two years
# ago that nobody took down, and the honest listings drown in them — the failure
# mode every classifieds site exists to avoid.
class ListingExpiryTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @seller = User.strict_loading(false).create!(
      email_address: "le_seller@brgen.no", password: "password123", city: @city
    )
    @category = Marketplace::Category.create!(name: "Diverse-#{SecureRandom.hex(3)}")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def listing(**attrs)
    Marketplace::Listing.create!({
      user: @seller, title: "Ting #{SecureRandom.hex(3)}", category: @category,
      price_cents: 10_000, status: "active"
    }.merge(attrs))
  end

  test "a new listing gets a window without being asked" do
    assert_in_delta Marketplace::Listing::LIFETIME.from_now.to_i, listing.expires_at.to_i, 5
  end

  # Expiry is a scope, not a state change — that is what lets an owner still see
  # and renew a lapsed listing.
  test "an expired listing leaves live but stays active for its owner" do
    fresh = listing
    lapsed = listing
    lapsed.update_columns(expires_at: 1.hour.ago)

    assert_includes Marketplace::Listing.live.map(&:id), fresh.id
    refute_includes Marketplace::Listing.live.map(&:id), lapsed.id
    assert_includes Marketplace::Listing.active.map(&:id), lapsed.id
    assert_includes Marketplace::Listing.expired.map(&:id), lapsed.id
    assert lapsed.reload.expired?
  end

  # Renewing late must not immediately expire again.
  test "renewing restarts the window from now" do
    lapsed = listing
    lapsed.update_columns(expires_at: 10.days.ago)

    lapsed.renew!
    assert_in_delta Marketplace::Listing::LIFETIME.from_now.to_i, lapsed.reload.expires_at.to_i, 5
    refute lapsed.expired?
    assert_includes Marketplace::Listing.live.map(&:id), lapsed.id
  end

  test "expiring_soon finds the ones inside the notice window and only once" do
    soon = listing
    soon.update_columns(expires_at: 3.days.from_now)
    far = listing

    assert_includes Marketplace::Listing.expiring_soon.map(&:id), soon.id
    refute_includes Marketplace::Listing.expiring_soon.map(&:id), far.id

    assert_difference -> { @seller.notifications.count }, 1 do
      ListingExpiryJob.perform_now
    end

    # Marked after sending, so a second run is quiet rather than a seller being
    # told every morning.
    assert_not_nil soon.reload.renewal_notice_sent_at
    assert_no_difference -> { @seller.notifications.count } do
      ListingExpiryJob.perform_now
    end
  end

  test "renewing clears the notice so the next lapse is announced again" do
    soon = listing
    soon.update_columns(expires_at: 3.days.from_now)
    ListingExpiryJob.perform_now
    assert_not_nil soon.reload.renewal_notice_sent_at

    soon.renew!
    assert_nil soon.reload.renewal_notice_sent_at
  end

  test "a shop page and a saved-search alert omit expired stock" do
    store = Marketplace::Store.create!(owner: @seller, name: "Butikk #{SecureRandom.hex(3)}")
    fresh = listing(store: store)
    lapsed = listing(store: store)
    lapsed.update_columns(expires_at: 1.hour.ago)

    assert_includes store.listings.live.map(&:id), fresh.id
    refute_includes store.listings.live.map(&:id), lapsed.id

    search = Marketplace::SavedSearch.create!(user: @seller, query: "Ting")
    search.update_columns(created_at: 1.day.ago, last_notified_at: 1.day.ago)
    ids = search.new_matches.map(&:id)
    assert_includes ids, fresh.id
    refute_includes ids, lapsed.id
  end

  test "strangers cannot view or order an expired listing; the owner still can" do
    lapsed = listing
    lapsed.update_columns(expires_at: 1.hour.ago)
    buyer = User.strict_loading(false).create!(
      email_address: "le_buyer@brgen.no", password: "password123", city: @city
    )

    refute Marketplace::ListingPolicy.new(buyer, lapsed).show?
    assert Marketplace::ListingPolicy.new(@seller, lapsed).show?
    refute lapsed.buyable?
    assert Marketplace::ListingPolicy.new(@seller, lapsed).renew?

    order = Marketplace::Order.new(buyer: buyer, listing: lapsed, status: "pending")
    assert_not order.valid?
    assert order.errors[:listing].any?
  end

  test "a deal on an expired listing is not live" do
    fresh = listing
    lapsed = listing
    lapsed.update_columns(expires_at: 1.hour.ago)
    live_deal = Marketplace::Deal.create!(listing: fresh, headline: "Live #{SecureRandom.hex(3)}")
    dead_deal = Marketplace::Deal.create!(listing: lapsed, headline: "Dead #{SecureRandom.hex(3)}")

    assert_includes Marketplace::Deal.live.map(&:id), live_deal.id
    refute_includes Marketplace::Deal.live.map(&:id), dead_deal.id
  end
end
