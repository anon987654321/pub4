# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# The order page offers accept and decline only on an open offer and a way to
# pay when payment can start; the deal page shows what the deal is worth and a
# way to buy; a grid card's Offer link reaches the listing's offer form.
class Marketplace::OrderAndDealPagesTest < ActionDispatch::IntegrationTest
  setup do
    host! "markedsplass.brgen.no"
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    @seller = User.create!(email_address: "od_seller_#{SecureRandom.hex(3)}@example.com", password: "secret1234")
    @buyer = User.create!(email_address: "od_buyer_#{SecureRandom.hex(3)}@example.com", password: "secret1234")
    @category = Marketplace::Category.create!(name: "Probe", slug: "od-#{SecureRandom.hex(4)}")
    @listing = Marketplace::Listing.create!(
      user: @seller, category: @category, title: "Freeride ski 180", price_cents: 20_000, stock: 3
    )
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "secret1234" }
  end

  def page = Nokogiri::HTML(response.body)

  def order(**attrs)
    Marketplace::Order.create!(listing: @listing, buyer: @buyer, quantity: 1, **attrs)
  end

  test "the seller answers an open offer, and declining asks first" do
    offer = order
    sign_in(@seller)
    get marketplace.order_path(offer)

    decline = page.at_css("form[action*='decline=true']")
    refute_nil decline, "an open offer offers no decline"
    assert_equal I18n.t("marketplace.confirm_decline"), decline["data-turbo-confirm"]
  end

  test "a paid order offers the seller no accept or decline" do
    paid = order(payment_status: "paid", status: "pending_payment")
    sign_in(@seller)
    get marketplace.order_path(paid)

    assert_nil page.at_css("form[action*='accept=true']")
    assert_nil page.at_css("form[action*='decline=true']")
  end

  test "a buyer whose payment failed is offered a way to pay" do
    failed = order(payment_status: "failed")
    sign_in(@buyer)
    Marketplace::Payments::StripeCheckout.stub(:configured?, true) do
      get marketplace.order_path(failed)
    end

    pay = page.at_css("form[action='#{marketplace.checkout_path}']")
    refute_nil pay, "a failed payment has no retry path"
    assert_equal failed.id.to_s, pay.at_css("input[name='order_id']")["value"]
  end

  test "the deal page shows the discount and a way to buy" do
    deal = Marketplace::Deal.create!(listing: @listing, headline: "Skisalg", discount_percent: 30,
                                     starts_at: 1.day.ago, ends_at: 3.days.from_now)
    sign_in(@buyer)
    get marketplace.deal_path(deal)

    assert_response :success
    assert_includes page.text, I18n.t("marketplace.percent_off", percent: 30)
    refute_nil page.at_css("form[action='#{marketplace.listing_orders_path(@listing)}']"), "no add-to-cart on the deal"
  end

  test "a grid card's offer link reaches the listing's offer form" do
    sign_in(@buyer)
    get marketplace.listings_path

    offer = page.css("a.deal-card-offer").find { _1["href"].include?(marketplace.listing_path(@listing)) }
    refute_nil offer, "the card's Offer link does not lead to its listing"
    assert offer["href"].end_with?("#make-offer")
  end
end
