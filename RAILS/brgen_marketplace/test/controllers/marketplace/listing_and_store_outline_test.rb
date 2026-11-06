# frozen_string_literal: true

require "test_helper"

# The listing page's sections are headings a reader can jump between, its
# statuses are words rather than column values, and a shop pages its listings
# and says so when it has none.
class Marketplace::ListingAndStoreOutlineTest < ActionDispatch::IntegrationTest
  setup do
    host! "markedsplass.brgen.no"
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    @seller = User.create!(email_address: "lo_seller_#{SecureRandom.hex(3)}@example.com", password: "secret1234")
    @buyer = User.create!(email_address: "lo_buyer_#{SecureRandom.hex(3)}@example.com", password: "secret1234")
    @category = Marketplace::Category.create!(name: "Probe", slug: "lo-#{SecureRandom.hex(4)}")
    @listing = Marketplace::Listing.create!(
      user: @seller, category: @category, title: "Freeride ski 180", price_cents: 20_000, stock: 3
    )
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "secret1234" }
  end

  def headings = Nokogiri::HTML(response.body).css("h2").map(&:text).map(&:strip)

  test "a buyer meets the questions and the offer form as headings" do
    sign_in(@buyer)
    get marketplace.listing_path(@listing)

    assert_includes headings, I18n.t("marketplace.questions")
    assert_includes headings, I18n.t("marketplace.make_offer")
  end

  test "the seller's dashboard and offers are headings with translated statuses" do
    Marketplace::Order.create!(listing: @listing, buyer: @buyer, quantity: 1)
    sign_in(@seller)
    get marketplace.listing_path(@listing)

    assert_includes headings, I18n.t("marketplace.seller_dashboard")
    assert_includes headings, I18n.t("marketplace.offers")
    text = Nokogiri::HTML(response.body).text
    assert_includes text, I18n.t("marketplace.listing_statuses.active")
    assert_includes text, "— #{I18n.t('marketplace.order_statuses.pending')}"
  end

  test "a shop with nothing live says so" do
    store = Marketplace::Store.create!(owner: @seller, name: "Tom butikk #{SecureRandom.hex(2)}")
    get marketplace.shop_path(store.slug)

    assert_response :success
    assert_includes response.body, I18n.t("marketplace.stores.no_listings")
  end

  test "a shop's listings page under their own key" do
    store = Marketplace::Store.create!(owner: @seller, name: "Stor butikk #{SecureRandom.hex(2)}")
    30.times do |i|
      Marketplace::Listing.create!(user: @seller, store:, category: @category, title: "Vare #{i}",
                                   price_cents: 1_000, stock: 1)
    end

    get marketplace.shop_path(store.slug)
    next_page = Nokogiri::HTML(response.body).at_css("a.pager-link[rel=next]")
    refute_nil next_page, "the shop's listings have no pager"
    assert_includes next_page["href"], "listings_page=2"

    get next_page["href"]
    assert_response :success
    assert_operator Nokogiri::HTML(response.body).css(".deal-grid .deal-card").size, :positive?
  end
end
