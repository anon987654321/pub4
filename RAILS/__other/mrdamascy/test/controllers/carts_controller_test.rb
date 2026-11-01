# frozen_string_literal: true

require "test_helper"

class CartsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = seed_kitchen!
    @category = seed_category!(@kitchen)
    @item = seed_item!(@category, name: "Damaskus Kylling Shawarma", price_ore: 12900)
  end

  test "add_item snapshots the price including paid options" do
    user = customer_sign_in
    extra_meat = seed_option!(@item, name: "Ekstra kjøtt", kind: "extra", price_ore: 2500)

    post add_item_cart_url, params: {
      menu_item_id: @item.id, quantity: 2, option_ids: [extra_meat.id], note: "Ekstra toum"
    }
    assert_includes [200, 302, 303], response.status

    cart = open_cart_for(user)
    assert_not_nil cart, "add_item must create the open cart for the signed-in user"

    line = cart.cart_items.sole
    assert_equal 2, line.quantity
    assert_equal 15400, line.unit_price_ore   # 12900 + 2500 option snapshot
    assert_equal 30800, line.line_total_ore
    assert_equal "Ekstra toum", line.note
  end

  test "add_item without options snapshots the plain price" do
    user = customer_sign_in

    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1, option_ids: [], note: "" }

    line = open_cart_for(user).cart_items.sole
    assert_equal 12900, line.unit_price_ore
  end

  test "update_item changes the quantity" do
    user = customer_sign_in
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1, option_ids: [], note: "" }
    line = open_cart_for(user).cart_items.sole

    patch update_item_cart_url(line.id), params: { quantity: 3 }

    assert_equal 3, line.reload.quantity
    assert_equal 38700, line.reload.line_total_ore
  end

  test "remove_item clears the line" do
    user = customer_sign_in
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1, option_ids: [], note: "" }
    line = open_cart_for(user).cart_items.sole

    delete remove_item_cart_url(line.id)

    assert_empty open_cart_for(user).reload.cart_items
  end

  test "cart page renders lines, totals and the Vipps CTA" do
    user = customer_sign_in
    cart = Cart.create!(user: user, delivery_mode: "delivery")
    CartItem.create!(cart: cart, menu_item: @item, quantity: 2,
                     unit_price_ore: 12900, option_ids: "")

    get cart_url
    assert_response :success

    assert_match "Damaskus Kylling Shawarma", response.body
    assert_match "258 kr", response.body       # subtotal 2 × 129 kr
    assert_match "Betal med Vipps", response.body
    assert_match "ingen kortfelter", response.body  # cart.steps_note
  end

  test "an empty cart invites you back to the menu" do
    customer_sign_in

    get cart_url
    assert_response :success
    assert_match(/tom|Meny|menyen/, response.body)
  end
end
