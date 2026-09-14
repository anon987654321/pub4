# frozen_string_literal: true

require "application_system_test_case"
require "minitest/mock"

# The marketplace purchase, driven in a browser from the listing to the PSP
# hand-off: add to cart, see the line and its total, pay with Stripe. Stripe
# itself is stubbed at StripeCheckout.start!, the one call that leaves the
# process, and Chrome is told checkout.stripe.com does not exist, so nothing
# reaches the network. What is asserted is what this side owns: the basket
# became a Checkout holding the order, and Stripe was asked to charge it.
class MarketplaceCheckoutTest < ApplicationSystemTestCase
  include CityHostSystemTest

  STRIPE_URL = "https://checkout.stripe.com/c/pay/cs_test_system"

  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    @city = City.find_by!(domain: "brgen.no")
    @buyer = person("checkout_buyer")
    @seller = person("checkout_seller")
    ActsAsTenant.with_tenant(@city) do
      category = Marketplace::Category.create!(name: "Sykler #{SecureRandom.hex(3)}")
      @listing = Marketplace::Listing.create!(
        user: @seller, title: "Racersykkel #{SecureRandom.hex(2)}", category: category,
        price_cents: 250_000, status: "active", currency: "NOK"
      )
    end
    Marketplace::Address.create!(user: @buyer, recipient: "Kari", line1: "Marken 4", postcode: "5017",
                                 city_name: "Bergen", country_code: "NO")
    @stripe_key_was = ENV["STRIPE_SECRET_KEY"]
    ENV["STRIPE_SECRET_KEY"] = "sk_test_system"
  end

  teardown do
    @stripe_key_was ? ENV["STRIPE_SECRET_KEY"] = @stripe_key_was : ENV.delete("STRIPE_SECRET_KEY")
  end

  test "a buyer adds a listing to the cart and pays the basket with Stripe" do
    sign_in_on_city(@buyer)
    visit_city("markedsplass", "/listings/#{@listing.to_param}")
    within(".listing-buy-bar") { click_button I18n.t("marketplace.add_to_cart") }
    assert wait_until { Marketplace::Order.exists?(buyer_id: @buyer.id, listing_id: @listing.id) },
           "add to cart created no order"

    visit_city("markedsplass", "/cart")
    assert_selector ".cart-item", text: @listing.title
    # The amount is set with non-breaking spaces, so compare with spacing folded.
    total = I18n.t("marketplace.cart_total", amount: Shared::MoneyDisplay.format(@listing.price_cents))
    assert_equal total.gsub(/[[:space:]]/, " "), find(".cart-summary > p:first-child strong").text.gsub(/[[:space:]]/, " ")

    charged = []
    start = lambda do |order:, success_url:, cancel_url:|
      charged << order
      STRIPE_URL
    end
    Marketplace::Payments::StripeCheckout.stub(:start!, start) do
      click_button I18n.t("marketplace.pay_stripe")
      assert wait_until { charged.any? }, "the pay button never reached Stripe"
    end

    checkout = charged.first
    assert_kind_of Marketplace::Checkout, checkout
    order = Marketplace::Order.find_by!(buyer_id: @buyer.id, listing_id: @listing.id)
    assert_equal checkout.id, order.marketplace_checkout_id
  end

  private

  def person(handle)
    User.strict_loading(false).create!(
      email_address: "#{handle}@brgen.no", password: "password123", username: handle, guest: false, city: @city
    )
  end
end
