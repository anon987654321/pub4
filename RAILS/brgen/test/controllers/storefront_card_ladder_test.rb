# frozen_string_literal: true

require "test_helper"

# Kaufland's density comes from every tile exposing the same fields in the same
# order, so the eye finds a price where it found the last one. The storefront
# tiles had the data and rendered it in a different order per surface: a deal
# put when it ends between its headline and what it sells, and its stars last.
#
# The ladder is the order, not the look. A tile shows the rungs it has data for,
# and a rung it lacks is skipped rather than faked — no reference price, shipping
# or delivery window is stored anywhere, so none is drawn. Price leads the title
# because layout_search holds that as a hard floor.
class StorefrontCardLadderTest < ActionDispatch::IntegrationTest
  LADDER = %w[deal-card-img deal-price deal-card-title deal-card-subtitle store-stars deal-meta store-badge].freeze

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    seller = User.strict_loading(false).create!(
      email_address: "cl_seller@brgen.no", password: "password123", username: "cl_seller", guest: false, city: @city
    )
    @bikes = Marketplace::Category.create!(name: "Sykler", slug: "sykler-#{SecureRandom.hex(4)}")
    listing = Marketplace::Listing.create!(user: seller, category: @bikes, title: "Racersykkel #{SecureRandom.hex(2)}",
                                           price_cents: 90_000, location: "Nordnes")
    listing.update_columns(rating: 4.5, reviews_count: 3)
    Marketplace::Deal.create!(listing:, headline: "Halv pris i helgen", discount_percent: 50, featured: true,
                              ends_at: 2.days.from_now)
    Marketplace::Store.create!(owner: seller, name: "Sykkelbutikken", slug: "sykkelbutikken-#{SecureRandom.hex(4)}",
                               vertical: "electronics", description: "Sykler og deler")
    @restaurant = Takeaway::Restaurant.create!(
      user: seller, name: "Suppekjøkkenet #{SecureRandom.hex(2)}", address: "Torget 2",
      cuisine_type: "Norwegian", city: @city, active: true, min_order_cents: 0
    )
    Takeaway::MenuItem.create!(restaurant: @restaurant, name: "Fiskesuppe", price_cents: 18_900, available: true,
                               description: "Med brød", vegetarian: false)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  # Document order, so a rung nested inside another is read where it sits.
  def rungs_in(card)
    card.xpath(".//*[@class]").filter_map { |node| LADDER.find { |rung| node["class"].split.include?(rung) } }
  end

  def assert_ladder(path)
    get path
    assert_response :success
    cards = css_select(".deal-card")
    assert cards.any?, "#{path} rendered no tile to measure"
    cards.each do |card|
      rungs = rungs_in(card)
      positions = rungs.map { |rung| LADDER.index(rung) }
      assert_equal positions.sort, positions, "#{path}: #{rungs.join(' → ')}"
    end
  end

  test "markedsplass tiles keep the ladder on every surface that draws them" do
    host! "markedsplass.brgen.no"

    assert_ladder marketplace.listings_path
    assert_ladder marketplace.deals_path
    assert_ladder marketplace.category_path(@bikes)
    assert_ladder marketplace.shops_path
  end

  test "a deal tile carries what it sells, its stars and its end in that order" do
    host! "markedsplass.brgen.no"
    get marketplace.deals_path

    deal = css_select(".deal-card.deal").first
    assert_equal %w[deal-card-img deal-price deal-card-title deal-card-subtitle store-stars deal-meta], rungs_in(deal).uniq
  end

  test "takeaway tiles keep the ladder" do
    host! "takeaway.brgen.no"

    assert_ladder takeaway.restaurants_path
    assert_ladder takeaway.restaurant_path(@restaurant)
  end
end
