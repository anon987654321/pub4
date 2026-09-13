# frozen_string_literal: true

require "test_helper"

# Deals are public and searchable by what they sell; delivery addresses are the
# buyer's own and nobody else's.
class MarketplaceDealsAndAddressesTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    @city = City.find_by!(domain: "brgen.no")
    @seller = create_user("md_seller")
    @buyer = create_user("md_buyer")
    @other = create_user("md_other")
    ActsAsTenant.current_tenant = @city
    category = Marketplace::Category.create!(name: "Møbler", slug: "mobler-#{SecureRandom.hex(4)}")
    @listing = Marketplace::Listing.create!(user: @seller, category: category,
                                            title: "Teakbord #{SecureRandom.hex(2)}", price_cents: 90_000)
    @deal = Marketplace::Deal.create!(listing: @listing, headline: "Halv pris i helgen", discount_percent: 50)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "markedsplass.brgen.no"
  end

  test "a guest sees the deals and one deal" do
    host! "markedsplass.brgen.no"

    get marketplace.deals_path
    assert_response :success
    assert_includes response.body, @deal.headline

    get marketplace.deal_path(@deal)
    assert_response :success
    assert_includes response.body, @listing.title
  end

  test "a deal is found by its headline or by the title of what it sells" do
    host! "markedsplass.brgen.no"

    get marketplace.deals_path(q: "Halv pris")
    assert_includes response.body, @deal.headline

    get marketplace.deals_path(q: "Teakbord")
    assert_includes response.body, @deal.headline

    get marketplace.deals_path(q: "Sofa")
    assert_not_includes response.body, @deal.headline
  end

  def address_params(recipient)
    { address: { recipient: recipient, line1: "Torget 1", postcode: "5003", city_name: "Bergen", country_code: "NO" } }
  end

  test "the first address saved becomes the default" do
    sign_in_as(@buyer)

    post marketplace.addresses_path, params: address_params("Kari")
    post marketplace.addresses_path, params: address_params("Ola")

    addresses = Marketplace::Address.where(user_id: @buyer.id).order(:id)
    assert_equal [ true, false ], addresses.map(&:default_address)
  end

  test "an address is the buyer's own to change or remove" do
    address = Marketplace::Address.create!(user: @buyer, recipient: "Kari", line1: "Torget 1",
                                           postcode: "5003", city_name: "Bergen", country_code: "NO")
    sign_in_as(@other)

    delete marketplace.address_path(address)
    assert_response :not_found
    assert Marketplace::Address.exists?(address.id)

    sign_in_as(@buyer)
    delete marketplace.address_path(address)
    assert_not Marketplace::Address.exists?(address.id)
  end
end
