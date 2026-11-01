# frozen_string_literal: true

require "test_helper"

# The crown test (APP_SPEC §14): the whole Vipps Express journey in one go —
# add to cart → checkout create (zone + min basket OK) → redirected to the
# mock Vipps page with a token → approve → payment captured + order confirmed
# → public tracking page says Sahtein! صحتين
class CheckoutFlowTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = seed_kitchen!
    # The tests post 5004 (Strandgaten) — the zone must cover the postcode the
    # checkout actually sends, and its minimum must admit the crown's single
    # 129 kr wrap; the dedicated min-basket test below works against this too.
    @zone = seed_zone!(postcode: "5004", fee_ore: 2900, min_basket_ore: 10000, eta_minutes: 20)
    @category = seed_category!(@kitchen)
    @item = seed_item!(@category, name: "Damaskus Kylling Shawarma", price_ore: 12900)
    seed_option!(@item, name: "Toum", kind: "sauce", default_on: true)
    @user = customer_sign_in
  end

  test "the crown: add to cart, pay with mock Vipps, confirm, track with Sahtein" do
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1,
                                      option_ids: [], note: "" }
    assert_includes [200, 302, 303], response.status

    cart = open_cart_for(@user)
    assert_not_nil cart
    assert_equal 1, cart.cart_items.count

    get checkout_url
    assert_response :success

    post checkout_url, params: { order: { address: "Nygårdsgaten 12", postcode: "5004",
                                          phone: "90000004", delivery_mode: "delivery" } }

    order = Order.order(:id).last
    assert_not_nil order, "checkout create must build an order from the cart"
    assert_equal @user.id, order.user_id
    assert_equal @kitchen.id, order.kitchen_id
    assert_equal "placed", order.state
    assert_equal "authorised", order.payment_state
    assert_equal true, order.express
    assert_equal 3, order.payment_steps
    assert_equal 12900, order.subtotal_ore
    assert_equal 2900, order.delivery_fee_ore
    assert_equal 0, order.discount_ore
    assert_equal 15800, order.total_ore
    assert_equal 1, order.order_items.count
    assert_equal @item.name, order.order_items.first.name
    assert_equal @item.price_ore, order.order_items.first.unit_price_ore

    assert_equal "mock-#{order.tracking_token}", order.vipps_order_id
    assert_match %r{/vipps/mock\?token=#{order.tracking_token}\z}, order.vipps_url
    assert_redirected_to order.vipps_url

    patch vipps_mock_approve_url, params: { token: order.tracking_token }
    assert_redirected_to track_path(order.tracking_token)
    assert_equal "captured", order.reload.payment_state
    assert_equal "confirmed", order.reload.state
    assert_match "Sahtein", flash.to_hash.values.map(&:to_s).join(" ")

    get track_url(order.tracking_token)
    assert_response :success
    assert_match(/Sahtein|صحتين/, response.body)
  end

  test "an unknown postcode re-renders the confirm screen and creates nothing" do
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1,
                                      option_ids: [], note: "" }

    post checkout_url, params: { order: { address: "Nygårdsgaten 12", postcode: "9999",
                                          phone: "90000004", delivery_mode: "delivery" } }

    assert_includes [200, 422], response.status, "zone failure should re-render, not redirect"
    assert_equal 0, Order.count
    combined = response.body + flash.to_hash.values.map(&:to_s).join(" ")
    assert_match(/leverer ikke/, combined)  # checkout.zone_fail / flash.zone_error
  end

  test "a basket below the zone minimum is refused" do
    cheap = seed_item!(@category, name: "Syltebolle", name_en: "Pickled cucumber",
                       price_ore: 2900, origin: "bergen", heat: 0, emoji: "🥒",
                       badges: "", weight_g: 100)
    post add_item_cart_url, params: { menu_item_id: cheap.id, quantity: 1,
                                      option_ids: [], note: "" }

    post checkout_url, params: { order: { address: "Nygårdsgaten 12", postcode: "5004",
                                          phone: "90000004", delivery_mode: "delivery" } }

    assert_includes [200, 422], response.status
    assert_equal 0, Order.count
    combined = response.body + flash.to_hash.values.map(&:to_s).join(" ")
    assert_match(/minstebestilling/i, combined)  # checkout.min_basket_fail / flash.min_basket
  end

  test "the best promo is auto-applied into the order totals" do
    seed_promo!(code: "SAHTEIN10", kind: "percent", value: 10)

    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1,
                                      option_ids: [], note: "" }
    post checkout_url, params: { order: { address: "Nygårdsgaten 12", postcode: "5004",
                                          phone: "90000004", delivery_mode: "delivery" } }

    order = Order.order(:id).last
    assert_equal "SAHTEIN10", order.promo_code
    assert_equal 1290, order.discount_ore      # 10 % of 129 kr
    assert_equal 12900 + 2900 - 1290, order.total_ore
  end

  test "the mock Vipps page answers 404 in real mode — no free captures" do
    order = seed_order!(kitchen: @kitchen, state: "placed")

    ENV["VIPPS_MOCK"] = "0"
    begin
      get vipps_mock_url, params: { token: order.tracking_token }
      assert_response :not_found

      patch vipps_mock_approve_url, params: { token: order.tracking_token }
      assert_response :not_found
    ensure
      ENV.delete("VIPPS_MOCK")
    end

    assert_equal "placed", order.reload.state, "mock approval must never fire in real mode"
    assert_equal "pending", order.reload.payment_state
  end
end
