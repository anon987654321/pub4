# frozen_string_literal: true

require "test_helper"

# "Yalla igjen": the whole last order back in the cart with one post.
class ReorderTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = seed_kitchen!
    category = seed_category!(@kitchen)
    @wrap = seed_item!(category, price_ore: 12_900)
    @toum = seed_option!(@wrap, name: "Toum", kind: "sauce")

    @fries = seed_item!(category, name: "Hvitløks-Pommes", price_ore: 5900, position: 2)
    @user = customer_sign_in

    @order = seed_order!(user: @user, kitchen: @kitchen, state: "delivered")
    @order.order_items.create!(menu_item_id: @wrap.id, name: @wrap.name, quantity: 2, unit_price_ore: 12_900,
                               line_total_ore: 25_800, options_text: "Toum", note: "Ekstra sterk")
    @order.order_items.create!(menu_item_id: @fries.id, name: @fries.name, quantity: 1, unit_price_ore: 5900,
                               line_total_ore: 5900)
  end

  test "the menu card posts the last order back into the cart" do
    get root_url
    form = Nokogiri::HTML(response.body).at_css(".reorder-card form")
    assert_equal reorder_cart_path, form["action"]
    assert_equal @order.id.to_s, form.at_css("input[name=order_id]")["value"]

    post reorder_cart_url, params: { order_id: @order.id }

    assert_redirected_to cart_path
    assert_equal I18n.t("flash.reordered"), flash[:notice]
    wrap_line = open_cart_for(@user).cart_items.find_by!(menu_item: @wrap)
    assert_equal [ 2, [ @toum.id ], "Ekstra sterk" ],
                 [ wrap_line.quantity, wrap_line.selected_option_ids, wrap_line.note ]
    assert open_cart_for(@user).cart_items.exists?(menu_item: @fries)
  end

  test "a dish off the menu today is left out and said so" do
    @fries.update!(available: false)

    post reorder_cart_url, params: { order_id: @order.id }

    assert_equal I18n.t("flash.reordered_partly"), flash[:notice]
    assert_equal [ @wrap.id ], open_cart_for(@user).cart_items.pluck(:menu_item_id)
  end

  test "another customer's order cannot be reordered" do
    other = seed_order!(kitchen: @kitchen, state: "delivered")

    post reorder_cart_url, params: { order_id: other.id }

    assert_redirected_to root_path
    assert_empty open_cart_for(@user)&.cart_items.to_a
  end
end
