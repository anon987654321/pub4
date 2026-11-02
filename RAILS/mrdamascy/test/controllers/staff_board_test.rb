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
    assert_includes [302, 303, 401, 403], response.status
  end

  test "anonymous visitors cannot open the board" do
    get staff_board_url
    assert_includes [302, 303, 401, 403], response.status
  end

  test "advancing an order requires the staff role" do
    customer_sign_in

    patch staff_advance_order_url(@order)

    assert_includes [302, 303, 401, 403], response.status
    assert_equal "placed", @order.reload.state, "customers must not move orders"
  end

  test "anonymous visitors cannot advance orders" do
    patch staff_advance_order_url(@order)

    assert_includes [302, 303, 401, 403], response.status
    assert_equal "placed", @order.reload.state
  end

  test "staff advances placed → confirmed" do
    staff_sign_in

    patch staff_advance_order_url(@order)

    assert_includes [200, 302, 303], response.status
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
end
