# frozen_string_literal: true

require "test_helper"

# The scheduled sweep calls recalculate! on every live listing every two
# hours. These tests pin the bound that makes that survivable: a listing whose
# score did not move keeps its updated_at, so its card fragments stay warm and
# SQLite keeps its pages; a moved score is written, timestamp and all.
class Marketplace::RankingServiceTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @seller = User.strict_loading(false).create!(email_address: "rank_seller@brgen.no", password: "password123", city: @city)
    @category = Marketplace::Category.create!(name: "Ranking-#{SecureRandom.hex(3)}")
    @listing = Marketplace::Listing.create!(
      user: @seller, category: @category, title: "Ranking probe", price_cents: 5_000, stock: 2
    )
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a recalculated score lands on the listing" do
    value = Marketplace::RankingService.new(@listing).recalculate!

    assert_equal value, @listing.reload.ranking_score
    assert_operator value, :>, 0
  end

  test "an unchanged score writes nothing, not even the timestamp" do
    Marketplace::RankingService.new(@listing).recalculate!
    frozen_at = @listing.reload.updated_at

    result = Marketplace::RankingService.new(@listing).recalculate!

    assert_equal frozen_at, @listing.reload.updated_at
    assert_equal @listing.ranking_score, result
  end

  test "a moved score is written with a fresh timestamp" do
    Marketplace::RankingService.new(@listing).recalculate!
    @listing.update_columns(seller_score: 1.0)
    stale_at = @listing.reload.updated_at

    Marketplace::RankingService.new(@listing).recalculate!

    assert_not_equal stale_at, @listing.reload.updated_at
  end
end
