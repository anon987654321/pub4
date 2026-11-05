# frozen_string_literal: true

require "test_helper"

# Checkout follows the kitchen's weekly hours once they are set: outside them
# the order is refused with when the kitchen opens. Empty hours, the live
# kitchen's default, leave ordering open at any hour.
class OpeningHoursTest < ActionDispatch::IntegrationTest
  WEEKDAYS = %w[11:00 21:00].freeze
  WEEKEND = %w[14:00 21:00].freeze

  setup do
    @kitchen = seed_kitchen!
    @item = seed_item!(seed_category!(@kitchen))
    customer_sign_in
  end

  def set_hours!
    hours = %w[mon tue wed thu fri].index_with { WEEKDAYS }.merge(%w[sat sun].index_with { WEEKEND })
    @kitchen.update!(weekly_hours: hours)
  end

  def order_pickup
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1, option_ids: [], note: "" }
    post checkout_url, params: { mode: "pickup", phone: "90000004" }
  end

  test "before opening on a weekday the order is refused with today's opening time" do
    set_hours!
    # 2026-11-04 is a Wednesday.
    travel_to(Time.zone.local(2026, 11, 4, 9, 30)) do
      assert_no_difference("Order.count") { order_pickup }
    end

    assert_redirected_to cart_path
    assert_equal I18n.t("checkout.opens_today", time: "11:00"), flash[:alert]
  end

  test "after closing on a Friday the next opening is Saturday afternoon" do
    set_hours!
    travel_to(Time.zone.local(2026, 11, 6, 22, 15)) do
      assert_no_difference("Order.count") { order_pickup }
    end

    assert_equal I18n.t("checkout.opens_on", day: "lørdag", time: "14:00"), flash[:alert]
  end

  test "inside the hours the order goes through" do
    set_hours!
    # 2026-11-07 is a Saturday.
    travel_to(Time.zone.local(2026, 11, 7, 15, 0)) do
      assert_difference("Order.count", 1) { order_pickup }
    end
  end

  test "the confirm screen says the kitchen is closed before the tap" do
    set_hours!
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1, option_ids: [], note: "" }
    travel_to(Time.zone.local(2026, 11, 4, 9, 30)) { get checkout_url }

    assert_select ".checkout-closed", text: I18n.t("checkout.opens_today", time: "11:00")
  end

  test "a kitchen with no hours set takes orders at any hour" do
    travel_to(Time.zone.local(2026, 11, 4, 3, 0)) do
      assert_difference("Order.count", 1) { order_pickup }
    end
  end

  test "hours must be weekday keys with an opening before a closing" do
    assert_not @kitchen.update(weekly_hours: { "mon" => %w[21:00 11:00] })
    assert_not @kitchen.update(weekly_hours: { "monday" => %w[11:00 21:00] })
    assert_not @kitchen.update(weekly_hours: { "mon" => %w[11 21] })
    assert @kitchen.update(weekly_hours: { "mon" => %w[11:00 21:00] })
  end
end
