# frozen_string_literal: true

require "test_helper"

# A double-tapped pay button posts the confirm form twice.
class CheckoutIdempotencyTest < ActionDispatch::IntegrationTest
  ADDRESS = { order: { address: "Nygårdsgaten 12", postcode: "5004", phone: "90000004",
                       delivery_mode: "delivery" } }.freeze

  setup do
    kitchen = seed_kitchen!
    seed_zone!(postcode: "5004", min_basket_ore: 10_000)
    @item = seed_item!(seed_category!(kitchen), price_ore: 12_900)
    @user = customer_sign_in
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1 }
    @cart = open_cart_for(@user)
  end

  test "a repeat post goes on to the order the first one placed" do
    post checkout_url, params: ADDRESS
    first = response.location
    order = Order.sole

    post checkout_url, params: ADDRESS

    assert_equal 1, Order.count, "the repeat post must not build a second order"
    assert_equal first, response.location
    assert_equal @cart.id, order.cart_id
  end

  test "a post while the first is still placing the order builds nothing" do
    @cart.update_columns(checkout_started_at: Time.current)

    post checkout_url, params: ADDRESS

    assert_equal 0, Order.count
    assert_redirected_to cart_path
    assert_equal I18n.t("checkout.in_progress"), flash[:alert]
    assert_equal 1, @cart.cart_items.count, "the cart is left for the first request"
  end

  test "a claim left by a crashed request expires and the cart is released after checkout" do
    @cart.update_columns(checkout_started_at: 3.minutes.ago)

    post checkout_url, params: ADDRESS

    assert_equal 1, Order.count
    assert_nil @cart.reload.checkout_started_at
  end
end
