# frozen_string_literal: true

require "test_helper"

# The category page names its count, sorts the three ways a buyer asks for,
# and offers the neighbouring categories beside the results.
class MarketplaceCategoryPageTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @seller = User.strict_loading(false).create!(
      email_address: "mc_seller@brgen.no", password: "password123", username: "mc_seller", guest: false
    )
    @parent = Marketplace::Category.create!(name: "Sport", slug: "sport-#{SecureRandom.hex(4)}")
    @bikes = Marketplace::Category.create!(name: "Sykler", slug: "sykler-#{SecureRandom.hex(4)}", parent: @parent)
    @skis = Marketplace::Category.create!(name: "Ski", slug: "ski-#{SecureRandom.hex(4)}", parent: @parent)
    @cheap = listing("Brukt sykkel", 40_000)
    @dear = listing("Racersykkel", 1_500_000)
    host! "markedsplass.brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def listing(title, price_cents)
    Marketplace::Listing.create!(user: @seller, category: @bikes, title: "#{title} #{SecureRandom.hex(2)}", price_cents:)
  end

  test "a leaf category shows its count, its siblings and its breadcrumb" do
    get marketplace.category_path(@bikes)

    assert_response :success
    assert_select "h1", text: @bikes.name
    assert_select ".store-results-count", text: I18n.t("marketplace.listing_count", count: 2)
    assert_select ".store-breadcrumb a[href=?]", marketplace.category_path(@parent)
    assert_select ".store-filters a[href=?]", marketplace.category_path(@skis)
    assert_select ".store-filters a[aria-current=page]", text: @bikes.name
  end

  test "price sort puts the cheapest first and marks itself current" do
    get marketplace.category_path(@bikes, sort: "price_low")

    assert_operator response.body.index(@cheap.title), :<, response.body.index(@dear.title)
    assert_select ".store-pills a.active[aria-current=page]", text: I18n.t("marketplace.sort_price_low")

    get marketplace.category_path(@bikes, sort: "price_high")
    assert_operator response.body.index(@dear.title), :<, response.body.index(@cheap.title)
  end

  test "an empty category says so rather than drawing an empty grid" do
    get marketplace.category_path(@skis)

    assert_response :success
    assert_includes response.body, I18n.t("empty.no_category")
    assert_select ".deal-grid", count: 0
  end
end
