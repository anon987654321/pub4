# frozen_string_literal: true

require "test_helper"

class Marketplace::SellerPerformanceTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @seller = User.strict_loading(false).create!(email_address: "perf_seller@brgen.no", password: "password123", city: @city)
    @buyer = User.strict_loading(false).create!(email_address: "perf_buyer@brgen.no", password: "password123", city: @city)
    @category = Marketplace::Category.create!(name: "Performance-#{SecureRandom.hex(3)}")
    @store = Marketplace::Store.create!(owner: @seller, name: "Performance Shop", slug: "perf-#{SecureRandom.hex(4)}")
    @listing = Marketplace::Listing.create!(user: @seller, store: @store, category: @category, title: "Performance listing", price_cents: 9_000, stock: 4)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def event(name, metadata: {})
    @listing.record_activity!(
      name,
      actor: @buyer,
      source_vertical: "marketplace",
      visibility: "private",
      metadata:
    )
  end

  test "summarises only private marketplace lifecycle events in the window" do
    event("MarketplacePurchaseCompleted")
    event("MarketplaceOrderShipped")
    event("MarketplaceOrderDelivered")
    event("MarketplaceReturnReceived")

    summary = Marketplace::SellerPerformance.new(@store).summary

    assert_equal 1, summary[:purchases]
    assert_equal 1, summary[:shipped]
    assert_equal 1, summary[:delivered]
    assert_equal 1, summary[:returns]
    assert_equal 1.0, summary[:delivery_completion_rate]
    assert_equal 1.0, summary[:return_rate]
  end

  test "reports paid sales from paid orders inside the window by currency" do
    current = Marketplace::Order.create!(buyer: @buyer, listing: @listing, price_cents: 8_500, quantity: 2)
    current.update!(payment_status: "paid", status: "paid", paid_at: Time.current)

    old = Marketplace::Order.create!(buyer: @buyer, listing: @listing, price_cents: 7_000, quantity: 3)
    old.update!(payment_status: "paid", status: "paid", paid_at: 61.days.ago)

    refunded = Marketplace::Order.create!(buyer: @buyer, listing: @listing, price_cents: 6_000, quantity: 4)
    refunded.update!(payment_status: "refunded", status: "completed", paid_at: Time.current)

    summary = Marketplace::SellerPerformance.new(@store).summary

    assert_equal({ "NOK" => 17_000 }, summary[:paid_sales_by_currency])
  end

  test "rates are nil without observations rather than being invented" do
    summary = Marketplace::SellerPerformance.new(@store).summary

    assert_nil summary[:delivery_completion_rate]
    assert_nil summary[:return_rate]
    assert_equal 0, summary[:review_count]
    assert_nil summary[:average_rating]
  end
end
