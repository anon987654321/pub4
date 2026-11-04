# frozen_string_literal: true

require "test_helper"

# The grey patterns stay grey only while the numbers are real. These tests pin
# the two model readers the cards render from: scarcity_quantity (real stock,
# never for one-of-a-kind or variant-managed listings) and the Omnibus anchor
# (the trailing 30-day observed minimum, rendered only when the current price
# is strictly below it). The persuasion_honesty source contract pins the rest.
class Marketplace::ListingPersuasionTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.with_tenant(@city) do
      seller = User.strict_loading(false).create!(email_address: "persuasion@brgen.no", password: "password123", city: @city)
      category = Marketplace::Category.create!(name: "Diverse-#{SecureRandom.hex(3)}")
      @listing = Marketplace::Listing.create!(user: seller, title: "Trillebør", category: category,
                                              price_cents: 50_000, status: "active", stock: 20)
    end
  end

  # Creation observes the price, so a test of older observations first moves that
  # one out of the window; otherwise the 500 kr listed today is the minimum.
  def listed_long_ago = @listing.price_observations.update_all(observed_at: 40.days.ago)

  test "a free listing records no price observation" do
    free = ActsAsTenant.with_tenant(@city) do
      Marketplace::Listing.create!(user: @listing.user, title: "Gis bort", category: @listing.category,
                                   price_cents: 0, status: "active")
    end

    assert_empty free.price_observations
    assert_nil free.omnibus_anchor_display
  end

  test "scarcity_quantity is nil for a one-of-a-kind listing" do
    ActsAsTenant.with_tenant(@city) do
      @listing.update!(stock: nil)
    end

    assert_nil @listing.scarcity_quantity
  end

  test "scarcity_quantity is the real count while stock is low" do
    ActsAsTenant.with_tenant(@city) do
      @listing.update!(stock: 3)
    end

    assert_equal 3, @listing.scarcity_quantity
  end

  test "scarcity_quantity is nil while stock is healthy" do
    assert_nil @listing.scarcity_quantity
  end

  # The anchor is only as honest as the observations are complete, so the
  # price the listing carries at creation is observed too, not just changes.
  test "a listing's price is observed at creation and on every change" do
    assert_equal [ 50_000 ], @listing.price_observations.order(:observed_at).map(&:price_cents)

    ActsAsTenant.with_tenant(@city) do
      @listing.update!(price_cents: 40_000)
    end

    assert_equal [ 50_000, 40_000 ], @listing.price_observations.order(:observed_at).map(&:price_cents)
  end

  test "the reference price ignores observations older than 30 days" do
    ActsAsTenant.with_tenant(@city) do
      listed_long_ago
      @listing.price_observations.create!(price_cents: 70_000, observed_at: 40.days.ago)
      @listing.price_observations.create!(price_cents: 55_000, observed_at: 2.days.ago)
    end

    assert_equal 55_000, @listing.omnibus_reference_price_cents
  end

  test "the anchor is nil while the current price is not below the observed minimum" do
    ActsAsTenant.with_tenant(@city) do
      @listing.price_observations.create!(price_cents: 45_000, observed_at: 2.days.ago)
    end

    assert_nil @listing.omnibus_anchor_display
  end

  test "the anchor renders the observed minimum when the current price is strictly below it" do
    ActsAsTenant.with_tenant(@city) do
      listed_long_ago
      @listing.price_observations.create!(price_cents: 60_000, observed_at: 2.days.ago)
    end

    anchor = @listing.omnibus_anchor_display
    assert anchor.present?
    assert anchor.include?("600"), "the anchor shows the observed 600 kr, not the current 500 kr"
  end
end
