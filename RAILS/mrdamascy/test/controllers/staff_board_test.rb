# frozen_string_literal: true

require "test_helper"

class StaffBoardTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = seed_kitchen!
    @order = seed_order!(kitchen: @kitchen, state: "placed")
  end

  test "the board requires the staff role" do
    customer_sign_in
    get staff_board_url
    assert_includes [ 302, 303, 401, 403 ], response.status
  end

  test "anonymous visitors cannot open the board" do
    get staff_board_url
    assert_includes [ 302, 303, 401, 403 ], response.status
  end

  test "advancing an order requires the staff role" do
    customer_sign_in

    patch staff_advance_order_url(@order)

    assert_includes [ 302, 303, 401, 403 ], response.status
    assert_equal "placed", @order.reload.state, "customers must not move orders"
  end

  test "anonymous visitors cannot advance orders" do
    patch staff_advance_order_url(@order)

    assert_includes [ 302, 303, 401, 403 ], response.status
    assert_equal "placed", @order.reload.state
  end

  test "staff advances placed → confirmed" do
    staff_sign_in

    patch staff_advance_order_url(@order)

    assert_includes [ 200, 302, 303 ], response.status
    assert_equal "confirmed", @order.reload.state
  end

  test "staff walks an order across the board to ready" do
    staff_sign_in

    get staff_board_url
    assert_response :success

    patch staff_advance_order_url(@order)
    assert_equal "confirmed", @order.reload.state
    patch staff_advance_order_url(@order)
    assert_equal "preparing", @order.reload.state
    patch staff_advance_order_url(@order)
    assert_equal "ready", @order.reload.state
  end

  test "the kitchen sees each line's options and the customer's note" do
    item = seed_item!(seed_category!(@kitchen), name: "Adana Sterk Dürüm")
    toum = seed_option!(item, name: "Toum", kind: "sauce")
    post add_item_cart_url, params: { menu_item_id: item.id, option_ids: [ toum.id ], note: "Uten løk" }
    post checkout_url, params: { mode: "pickup", phone: "90000031" }
    order = Order.order(:id).last

    staff_sign_in
    get staff_board_url
    card = Nokogiri::HTML(response.body).at_css("#order_card_#{order.id}")

    assert_equal "Toum", card.at_css(".board-card-options")&.text
    assert_equal "Uten løk", card.at_css(".board-card-note")&.text
  end

  test "a Wolt dispatch names the courier Wolt gave and the card dials the phone" do
    staff_sign_in
    @order.update!(state: "ready")

    patch staff_wolt_order_url(@order)
    assert_equal "Bergen Bud", @order.reload.courier_name

    @order.update!(courier_name: "Amina")
    get staff_board_url
    card = Nokogiri::HTML(response.body).at_css("#order_card_#{@order.id}")
    assert_includes card.at_css(".board-wait").text, "Amina"
    assert card.at_css(%(.board-card-phone a[href="tel:90000004"]))
  end
end
