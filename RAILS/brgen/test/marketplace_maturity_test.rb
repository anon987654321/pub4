# frozen_string_literal: true

require "test_helper"

class MarketplaceMaturityTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @seller = User.strict_loading(false).create!(
      email_address: "maturity_seller_#{SecureRandom.hex(3)}@brgen.no",
      password: "password123",
      username: "maturity_seller_#{SecureRandom.hex(3)}",
      guest: false
    )
    @buyer = User.strict_loading(false).create!(
      email_address: "maturity_buyer_#{SecureRandom.hex(3)}@brgen.no",
      password: "password123",
      username: "maturity_buyer_#{SecureRandom.hex(3)}",
      guest: false
    )
    @category = Marketplace::Category.create!(name: "Maturity-#{SecureRandom.hex(3)}")
    @listing = Marketplace::Listing.create!(
      user: @seller,
      title: "Maturity bicycle",
      description: "A fast city bicycle",
      category: @category,
      price_cents: 20_000,
      status: "active",
      currency: "NOK",
      delivery_promise: Marketplace::Listing::DELIVERY_PROMISES[:next_day_bergen],
      fulfilment_method: Marketplace::Listing::FULFILMENT_METHODS[:local_hub]
    )
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "listing events are persisted and included in ranking performance" do
    4.times { @listing.record_event!("click", user: @buyer) }
    @listing.record_event!("cart", user: @buyer)

    assert_equal 5, @listing.events.recent(7).count
    assert_equal 4, @listing.events.of_type("click").count

    score = Marketplace::RankingService.new(@listing).score
    assert_operator score, :>, 0.0
    assert_equal "I morgen i Bergen", @listing.delivery_badge
  end

  test "ranking recalculation persists a bounded score" do
    score = Marketplace::RankingService.new(@listing, query: "bicycle").recalculate!

    assert_equal score, @listing.reload.ranking_score
    assert_operator score, :>=, 0.0
    assert_operator score, :<=, 1.0
  end

  test "seller score calculator reads listing events without a PostgreSQL-only query" do
    @listing.record_event!("purchase", user: @buyer)
    @listing.record_event!("shipped", user: @seller)
    @listing.record_event!("delivered", user: @buyer)

    score = Marketplace::SellerScoreCalculator.new(@seller).score

    assert_operator score, :>=, 0.2
    assert_operator score, :<=, 1.0
  end

  test "request-time relevance outranks an unrelated global quality prior" do
    chair = Marketplace::Listing.create!(
      user: @seller,
      title: "Maturity chair",
      description: "A simple chair",
      category: @category,
      price_cents: 5_000,
      status: "active",
      currency: "NOK",
      delivery_promise: Marketplace::Listing::DELIVERY_PROMISES[:three_to_five_days],
      fulfilment_method: Marketplace::Listing::FULFILMENT_METHODS[:self_ship],
      ranking_score: 0.95
    )
    @listing.update_columns(ranking_score: 0.20)

    ranked = Marketplace::SearchRanker.new(
      Marketplace::Listing.where(id: [ @listing.id, chair.id ]),
      query: "bicycle"
    ).relation.to_a

    assert_equal @listing.id, ranked.first.id
    reasons = Marketplace::SearchRanker.new(
      Marketplace::Listing.where(id: [ @listing.id ]),
      query: "bicycle"
    ).reasons(@listing)
    assert reasons.any? { |reason| reason.downcase.include?("search") }
  end
end
