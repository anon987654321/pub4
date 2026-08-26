# frozen_string_literal: true

require "test_helper"

# The cart's pay buttons POST without an order_id, which now means "pay the
# whole basket" rather than "pay whichever line happens to be first".
class MarketplaceBasketTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @buyer = User.strict_loading(false).create!(
      email_address: "mb_buyer@brgen.no", password: "password123", username: "mb_buyer", guest: false
    )
    @seller = User.strict_loading(false).create!(
      email_address: "mb_seller@brgen.no", password: "password123", username: "mb_seller", guest: false
    )
    ActsAsTenant.current_tenant = @city
    @category = Marketplace::Category.create!(name: "Diverse-#{SecureRandom.hex(3)}")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def listing(price: 20_000)
    Marketplace::Listing.create!(
      user: @seller, title: "Ting #{SecureRandom.hex(3)}", category: @category,
      price_cents: price, status: "active", currency: "NOK"
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  def in_market
    host! "markedsplass.brgen.no"
  end

  test "the addresses page saves one and makes the first the default" do
    sign_in_as(@buyer)
    in_market

    assert_difference -> { Marketplace::Address.count }, 1 do
      post marketplace.addresses_path, params: { address: {
        recipient: "Kari", line1: "Marken 4", postcode: "5017", city_name: "Bergen", country_code: "NO"
      } }
    end
    # Making someone tick a box on a list of one is ceremony.
    assert @buyer.marketplace_addresses.first.default_address?
  end

  test "a basket with no address sends the buyer to add one rather than to a PSP" do
    Marketplace::Order.create!(buyer: @buyer, listing: listing, quantity: 1, price_cents: 20_000)
    sign_in_as(@buyer)
    in_market

    assert_no_difference -> { Marketplace::Checkout.count } do
      post marketplace.checkout_path, params: { provider: "vipps" }
    end
    # Not a DoubleRenderError, which is what checking this after the
    # nothing-payable branch produced: a 500 for a buyer who had not
    # saved an address.
    assert_response :redirect
  end

  test "an empty cart is reported before anything about payment providers" do
    sign_in_as(@buyer)
    in_market

    post marketplace.checkout_path, params: { provider: "stripe" }
    assert_redirected_to marketplace.cart_path
    assert_equal I18n.t("flash.marketplace.cart_not_payable"), flash[:alert]
  end

  test "an unknown provider is refused without assembling a basket" do
    Marketplace::Order.create!(buyer: @buyer, listing: listing, quantity: 1, price_cents: 20_000)
    sign_in_as(@buyer)
    in_market

    assert_no_difference -> { Marketplace::Checkout.count } do
      post marketplace.checkout_path, params: { provider: "monopoly-money" }
    end
    assert_redirected_to marketplace.cart_path
  end

  test "the cart shows the delivery address it will use" do
    @buyer.marketplace_addresses.create!(
      recipient: "Kari", line1: "Marken 4", postcode: "5017", city_name: "Bergen",
      country_code: "NO", default_address: true
    )
    Marketplace::Order.create!(buyer: @buyer, listing: listing, quantity: 1, price_cents: 20_000)
    sign_in_as(@buyer)
    in_market

    get marketplace.cart_path
    assert_response :success
    assert_match "Marken 4", response.body
  end
end
