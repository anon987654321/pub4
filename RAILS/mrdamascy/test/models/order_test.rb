# frozen_string_literal: true

require "test_helper"

class OrderTest < ActiveSupport::TestCase
  setup do
    @user = seed_customer!(name: "Ola Nordmann")
    @kitchen = seed_kitchen!
    @zone = seed_zone!(postcode: "0170", fee_ore: 2900, min_basket_ore: 15000, eta_minutes: 20)
    @category = seed_category!(@kitchen)
    @cart = Cart.create!(user: @user, delivery_mode: "delivery")
  end

  def add_line(quantity: 1, price_ore: 12900)
    item = seed_item!(@category, price_ore: price_ore)
    CartItem.create!(cart: @cart, menu_item: item, quantity: quantity,
                     unit_price_ore: price_ore, option_ids: "")
  end

  # -- Defaults -------------------------------------------------------------

  test "a fresh order defaults to placed / pending / express / 3 payment steps" do
    order = Order.new
    assert_equal "placed", order.state
    assert_equal "pending", order.payment_state
    assert_equal 3, order.payment_steps
    assert_equal true, order.express
    assert_equal 0, order.tip_ore
    assert_equal 0, order.discount_ore
  end

  # -- Totals ---------------------------------------------------------------

  test "snapshot + compute_totals! sets subtotal, fee, discount, total and eta" do
    add_line(quantity: 1, price_ore: 12900)
    add_line(quantity: 2, price_ore: 4900)

    order = Order.new(user: @user, kitchen: @kitchen, delivery_mode: "delivery",
                      address: "Nygårdsgaten 12", postcode: "5004", phone: "90000004")
    order.snapshot_from_cart!(@cart)
    order.compute_totals!(@zone)

    assert_equal 2, order.order_items.count  # frozen snapshots of the cart lines
    assert_equal 22700, order.subtotal_ore   # 12900 + 2 × 4900
    assert_equal 2900, order.delivery_fee_ore
    assert_equal 0, order.discount_ore       # no promo result passed — hermetic
    assert_equal 25600, order.total_ore      # subtotal − discount + fee
    assert_equal 20, order.eta_minutes
  end

  test "pickup orders carry no delivery fee and no eta" do
    add_line(quantity: 1, price_ore: 12900)
    order = Order.new(user: @user, kitchen: @kitchen, delivery_mode: "pickup",
                      address: nil, postcode: nil, phone: "90000004")
    order.snapshot_from_cart!(@cart)
    order.compute_totals!(@zone)

    assert_equal 0, order.delivery_fee_ore
    assert_nil order.eta_minutes
    assert_equal 12900, order.total_ore
  end

  test "apply_promo_result! lands the promo in the order" do
    order = seed_order!(user: @user, kitchen: @kitchen)
    promo = seed_promo!(code: "SAHTEIN10", kind: "percent", value: 10)

    order.apply_promo_result!(promo: promo, discount_ore: 1290, delivery_fee_ore: 2900)

    assert_equal "SAHTEIN10", order.promo_code
    assert_equal 1290, order.discount_ore
  end

  # The payment is captured before delivery and no lane can charge again, so
  # the tip is kept beside the total, never in it.
  test "add_tip! records one tip on a delivered order and leaves the paid total alone" do
    add_line(quantity: 1, price_ore: 12_900)
    order = Order.new(user: @user, kitchen: @kitchen, delivery_mode: "delivery",
                      address: "Nygårdsgaten 12", postcode: "5004", phone: "90000004")
    order.snapshot_from_cart!(@cart)
    order.compute_totals!(@zone)
    assert_equal 15_800, order.total_ore

    assert_raises(Order::InvalidTransition) { order.add_tip!(2000) }
    order.update!(state: "delivered")

    assert_raises(ArgumentError) { order.add_tip!(0) }
    assert_raises(ArgumentError) { order.add_tip!(-500) }
    order.add_tip!(2000)
    assert_equal 2000, order.reload.tip_ore
    assert_equal 15_800, order.total_ore

    assert_raises(Order::InvalidTransition) { order.add_tip!(4000) }
    assert_equal 2000, order.reload.tip_ore
  end

  # -- State machine --------------------------------------------------------

  test "advance! walks placed → confirmed → preparing → ready" do
    order = seed_order!(user: @user, kitchen: @kitchen)

    order.advance!
    assert_equal "confirmed", order.reload.state
    order.advance!
    assert_equal "preparing", order.reload.state
    order.advance!
    assert_equal "ready", order.reload.state
  end

  test "invalid jumps are refused" do
    order = seed_order!(user: @user, kitchen: @kitchen, state: "placed")
    refuse_transition(order, :pickup!)   # courier may not skip the kitchen
    refuse_transition(order, :deliver!)

    ready = seed_order!(user: @user, kitchen: @kitchen, state: "ready")
    refuse_transition(ready, :advance!)  # staff stops at ready — courier takes over
    refuse_transition(ready, :deliver!)  # deliver! requires picked_up

    cooking = seed_order!(user: @user, kitchen: @kitchen, state: "preparing")
    refuse_transition(cooking, :cancel!) # too late to cancel once the grill is hot
  end

  test "cancel! works before the kitchen starts and lands on cancelled" do
    order = seed_order!(user: @user, kitchen: @kitchen, state: "placed")
    order.cancel!
    assert_equal "cancelled", order.reload.state
  end

  test "pickup! and deliver! carry courier transitions" do
    order = seed_order!(user: @user, kitchen: @kitchen, state: "ready")
    order.pickup!
    assert_equal "picked_up", order.reload.state
    order.deliver!
    assert_equal "delivered", order.reload.state
  end

  test "each move keeps its own moment" do
    order = seed_order!(user: @user, kitchen: @kitchen, state: "placed")
    times = {}
    travel_to(Time.zone.local(2026, 11, 4, 12, 0)) { order.advance!; times[:confirmed_at] = Time.current }
    travel_to(Time.zone.local(2026, 11, 4, 12, 3)) { order.advance! }
    travel_to(Time.zone.local(2026, 11, 4, 12, 15)) { order.advance!; times[:ready_at] = Time.current }
    travel_to(Time.zone.local(2026, 11, 4, 12, 20)) { order.pickup!; times[:picked_up_at] = Time.current }
    travel_to(Time.zone.local(2026, 11, 4, 12, 35)) { order.deliver!; times[:delivered_at] = Time.current }

    order.reload
    times.each { |column, moment| assert_equal moment, order.public_send(column), column }
  end

  test "delivering awards exactly one loyalty stamp to the order's user" do
    order = seed_order!(user: @user, kitchen: @kitchen, state: "ready")

    assert_difference "LoyaltyStamp.count", 1 do
      order.pickup!
      order.deliver!
    end

    stamp = LoyaltyStamp.find_by(order: order, user: @user)
    assert_not_nil stamp
    assert_not stamp.redeemed
    assert stamp.awarded_at.present?
  end

  test "a delivered order's stamp is awarded once however often it is asked for" do
    order = seed_order!(user: @user, kitchen: @kitchen, state: "picked_up")
    order.deliver!

    assert_no_difference "LoyaltyStamp.count" do
      order.award_stamp!
    end
    assert_equal 1, @user.stamp_count
  end

  # The card's stated rule is the one the code keeps: every delivered order
  # earns a star, whatever it cost, so the rule names no amount.
  test "a small delivered order earns its star, and the card's rule names no minimum" do
    order = seed_order!(user: @user, kitchen: @kitchen, state: "picked_up")
    order.update!(subtotal_ore: 4_900, total_ore: 4_900)

    assert_difference "@user.stamp_count", 1 do
      order.deliver!
    end
    %i[nb en].each do |locale|
      rule = I18n.t("loyalty.rule_one", locale:)
      assert_no_match(/\d/, rule, "#{locale} loyalty.rule_one promises a minimum the code does not keep")
    end
  end

  # -- Tracking token -------------------------------------------------------

  test "tracking tokens are unique" do
    seed_order!(user: @user, kitchen: @kitchen, token: "tokendupl1")
    duplicate = Order.new(user: @user, kitchen: @kitchen, delivery_mode: "delivery",
                          address: "Nygårdsgaten 12", postcode: "5004", phone: "90000004",
                          subtotal_ore: 12900, delivery_fee_ore: 2900, total_ore: 15800,
                          tracking_token: "tokendupl1")
    assert_not duplicate.valid?, "two orders must never share a tracking token"
  end

  test "new orders get distinct tracking tokens" do
    a = seed_order!(user: @user, kitchen: @kitchen, token: nil)
    b = seed_order!(user: @user, kitchen: @kitchen, token: nil)

    assert a.reload.tracking_token.present?, "tracking_token must be auto-generated"
    assert b.reload.tracking_token.present?
    assert_not_equal a.tracking_token, b.tracking_token
  end

  private

  # Guards may raise or return false — both count as a refusal. What must
  # never happen is the state silently moving to an illegal value.
  def refuse_transition(order, method)
    before = order.state
    begin
      order.public_send(method)
    rescue StandardError
      # raised guard — fine
    end
    order.reload
    assert_equal before, order.state, "#{method} should be refused from #{before}"
  end
end
