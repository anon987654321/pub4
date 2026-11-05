# frozen_string_literal: true

require "test_helper"

# The Sahtein card at checkout: nine stamps make the next wrap free, and that
# wrap spends them. Before the stamps were spent, every order after the ninth
# stamp got its wrap for nothing.
class LoyaltyCheckoutTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = seed_kitchen!
    @item = seed_item!(seed_category!(@kitchen), name: "Damaskus Kylling Shawarma", price_ore: 12_900)
    @user = customer_sign_in
    9.times { |n| LoyaltyStamp.create!(user: @user, awarded_at: n.days.ago) }
  end

  def place_pickup_order
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1, option_ids: [], note: "" }
    post checkout_url, params: { mode: "pickup", phone: "90000004" }
    Order.order(:id).last
  end

  test "the tenth stamp redeems as a free wrap at checkout and spends the nine stamps" do
    order = place_pickup_order

    assert_equal 12_900, order.discount_ore, "the cheapest wrap is on the house"
    assert_equal 0, order.total_ore
    assert_equal 0, @user.reload.unredeemed_stamp_count
    assert_equal 9, order.redeemed_stamps.count
  end

  # Vipps and Stripe refuse a 0 kr payment, so a free wrap and nothing else
  # never goes to either: it is settled at checkout and confirmed for the
  # kitchen, with no payment page to send the customer to.
  test "a 0 kr free-wrap order skips the payment and is confirmed at once" do
    vipps_real_mode!
    order = place_pickup_order

    assert_redirected_to track_path(order.tracking_token)
    assert_empty vipps_calls, "a 0 kr order reached Vipps"
    assert_equal "captured", order.payment_state
    assert_equal "confirmed", order.state
    assert_nil order.vipps_url
  ensure
    vipps_restore_http!
  end

  test "a cancelled 0 kr order owes no refund" do
    order = place_pickup_order
    order.cancel!

    assert_nil order.reload.refund_state
    assert_not_includes Order.refunds_due, order
  end

  test "the order after the free wrap pays full price" do
    place_pickup_order
    second = place_pickup_order

    assert_equal 0, second.discount_ore
    assert_equal 12_900, second.total_ore
  end

  test "the free wrap's own delivery stamp is the tenth one and the card starts over" do
    order = place_pickup_order
    order.update!(state: "picked_up")

    assert_difference "LoyaltyStamp.count", 1 do
      order.deliver!
    end
    assert_equal 0, @user.reload.unredeemed_stamp_count
    assert_equal 10, @user.stamp_count
  end

  test "a cancelled free-wrap order gives its stamps back" do
    order = place_pickup_order
    order.cancel!

    assert_equal 9, @user.reload.unredeemed_stamp_count
    assert_empty order.redeemed_stamps.reload
  end
end
