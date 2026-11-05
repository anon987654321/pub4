# frozen_string_literal: true

require "application_system_test_case"

# One pickup order the way a customer places it: menu, item sheet, cart,
# checkout, the mock Vipps approval, and the tracking page.
class PickupOrderTest < ApplicationSystemTestCase
  setup do
    kitchen = seed_kitchen!
    @item = seed_item!(seed_category!(kitchen), name: "Damaskus Kylling Shawarma", price_ore: 12_900)
    seed_option!(@item, name: "Toum", kind: "sauce")
  end

  test "a guest orders a wrap for pickup from the menu to tracking" do
    visit root_path
    click_on I18n.t("menu.customize")

    assert_selector "h1.sheet-name", text: @item.name
    check "Toum"
    click_on I18n.t("menu.add_with_price", price: "129 kr")

    # The sheet stays and the tab bar's cart tab counts the dish.
    open_cart_from_tab_bar
    assert_text @item.name
    click_on I18n.t("checkout.mode_pickup")

    assert_current_path checkout_path(mode: "pickup")
    fill_in "phone", with: "90000004"
    click_on I18n.t("checkout.vipps_cta_total", total: "129 kr")

    assert_selector ".vipps-mock"
    order = Order.order(:id).last
    assert_equal "pickup", order.delivery_mode
    assert_equal [ "Toum" ], order.order_items.pluck(:options_text)

    click_on I18n.t("vipps.approve")
    assert_current_path track_path(order.tracking_token)
    assert_text I18n.t("orders.states.confirmed")
    assert_equal "captured", order.reload.payment_state
  end
end
