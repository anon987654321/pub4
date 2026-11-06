# frozen_string_literal: true

require "test_helper"

# The crown test (APP_SPEC §14): the whole Vipps Express journey in one go —
# add to cart → checkout create (zone + min basket OK) → redirected to the
# mock Vipps page with a token → approve → payment captured + order confirmed
# → public tracking page says Sahtein! صحتين
class CheckoutFlowTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = seed_kitchen!
    # The tests post 5004 (Strandgaten) — a real delivery zone one district away
    # checkout actually sends, and its minimum must admit the crown's single
    # 129 kr wrap; the dedicated min-basket test below works against this too.
    @zone = seed_zone!(postcode: "5004", fee_ore: 2900, min_basket_ore: 10000, eta_minutes: 20)
    @category = seed_category!(@kitchen)
    @item = seed_item!(@category, name: "Damaskus Kylling Shawarma", price_ore: 12900)
    seed_option!(@item, name: "Toum", kind: "sauce", default_on: true)
    @user = customer_sign_in
  end

  teardown do
    # The real-mode tracking test turns STRIPE_MOCK off; without this restore
    # the env leaks into whichever test minitest shuffles next (the crown's
    # card lane would then hit real HTTP and stay "pending").
    stripe_restore_http!
  end

  test "the crown: add to cart, pay with mock Vipps, confirm, track with Sahtein" do
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1,
                                      option_ids: [], note: "" }
    assert_includes [ 200, 302, 303 ], response.status

    cart = open_cart_for(@user)
    assert_not_nil cart
    assert_equal 1, cart.cart_items.count

    get checkout_url
    assert_response :success

    post checkout_url, params: { order: { address: "Nygårdsgaten 12", postcode: "5004",
                                          phone: "90000004", delivery_mode: "delivery" } }

    order = Order.order(:id).last
    assert_not_nil order, "checkout create must build an order from the cart"
    assert_equal "vipps", order.payment_method, "Vipps stays the default lane"
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

  # The confirm form posts plain fields and names its radios `mode`; the tests
  # above post order[delivery_mode], which the form never sends, so choosing
  # pickup on the real page placed a delivery order.
  test "choosing pickup on the confirm form places a pickup order" do
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1, option_ids: [], note: "" }

    assert_difference -> { Order.count }, 1 do
      post checkout_url, params: { mode: "pickup", phone: "90000004" }
    end
    assert_equal "pickup", Order.order(:id).last.delivery_mode
  end

  test "an unknown postcode re-renders the confirm screen and creates nothing" do
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1,
                                      option_ids: [], note: "" }

    post checkout_url, params: { order: { address: "Nygårdsgaten 12", postcode: "9999",
                                          phone: "90000004", delivery_mode: "delivery" } }

    assert_includes [ 200, 422 ], response.status, "zone failure should re-render, not redirect"
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

    assert_includes [ 200, 422 ], response.status
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

  test "the crown, card lane: add to cart, pay with mock Stripe, confirm, track" do
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1,
                                      option_ids: [], note: "" }

    post checkout_url, params: { order: { address: "Nygårdsgaten 12", postcode: "5004",
                                          phone: "90000004", delivery_mode: "delivery",
                                          payment_method: "stripe" } }

    order = Order.order(:id).last
    assert_not_nil order, "checkout create must build an order from the cart"
    assert_equal "stripe", order.payment_method
    assert_equal "authorised", order.payment_state
    assert_equal 15800, order.total_ore, "totals math is identical on both lanes"
    assert_equal "mock-stripe-#{order.tracking_token}", order.vipps_order_id
    assert_match %r{/stripe/mock\?token=#{order.tracking_token}\z}, order.vipps_url
    assert_redirected_to order.vipps_url

    patch stripe_mock_approve_url, params: { token: order.tracking_token }
    assert_redirected_to track_path(order.tracking_token)
    assert_equal "captured", order.reload.payment_state
    assert_equal "confirmed", order.reload.state

    get track_url(order.tracking_token)
    assert_response :success
    assert_match(/Sahtein|صحتين/, response.body)
  end

  test "an unknown payment_method falls back to the Vipps lane" do
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1,
                                      option_ids: [], note: "" }

    post checkout_url, params: { order: { address: "Nygårdsgaten 12", postcode: "5004",
                                          phone: "90000004", delivery_mode: "delivery",
                                          payment_method: "paypal" } }

    order = Order.order(:id).last
    assert_equal "vipps", order.payment_method, "tampered PSP values must not select a lane"
    assert_match %r{/vipps/mock}, order.vipps_url
  end

  test "the mock Stripe page answers 404 in real mode — no free captures" do
    order = seed_order!(kitchen: @kitchen, state: "placed", token: "tok-stripe-guard")

    ENV["STRIPE_MOCK"] = "0"
    begin
      get stripe_mock_url, params: { token: order.tracking_token }
      assert_response :not_found

      patch stripe_mock_approve_url, params: { token: order.tracking_token }
      assert_response :not_found
    ensure
      ENV.delete("STRIPE_MOCK")
    end

    assert_equal "placed", order.reload.state, "mock approval must never fire in real mode"
    assert_equal "pending", order.reload.payment_state
  end

  test "the tracking page completes a real-mode Stripe payment via the sync seam" do
    order = seed_order!(kitchen: @kitchen, state: "placed", token: "tok-stripe-poll")
    order.update!(payment_method: "stripe", payment_state: "authorised",
                  vipps_order_id: "cs_test_poll")
    stripe_real_mode!

    get track_url(order.tracking_token)

    assert_response :success
    @order = order.reload
    assert_equal "captured", @order.payment_state
    assert_equal "confirmed", @order.state
  end
end
