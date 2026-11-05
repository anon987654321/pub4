# frozen_string_literal: true

require "application_system_test_case"

# axe-core over the five screens an order passes through: menu, item sheet,
# cart, checkout and tracking.
class AccessibilityTest < ApplicationSystemTestCase
  setup do
    kitchen = seed_kitchen!
    @item = seed_item!(seed_category!(kitchen))
    seed_option!(@item, name: "Toum", kind: "sauce")
  end

  test "the menu has no axe-core violations" do
    visit root_path
    assert_selector ".item-card"
    assert_accessible
  end

  test "the item sheet has no axe-core violations" do
    visit menu_item_path(@item)
    assert_selector ".sheet-allergens"
    assert_accessible
  end

  test "the cart and the checkout have no axe-core violations" do
    visit menu_item_path(@item)
    click_on I18n.t("menu.add_with_price", price: "129 kr")
    open_cart_from_tab_bar
    assert_accessible

    visit checkout_path(mode: "pickup")
    assert_selector ".checkout-form"
    assert_accessible
  end

  test "the tracking page has no axe-core violations" do
    order = seed_order!(state: "preparing")

    visit track_path(order.tracking_token)
    assert_selector ".timeline"
    assert_accessible
  end
end
