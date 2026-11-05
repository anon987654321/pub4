# frozen_string_literal: true

require "test_helper"

# The board's cancel button (Order#cancel! had no caller). Neither payment
# client can refund, so a paid order is cancelled owing a manual refund, the
# toast says where to make it, and the refunds list keeps it until marked.
class StaffCancelTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = seed_kitchen!
    @order = seed_order!(kitchen: @kitchen, state: "placed")
  end

  test "only staff can cancel" do
    customer_sign_in

    patch staff_cancel_order_url(@order)

    assert_includes [ 302, 303, 401, 403 ], response.status
    assert_equal "placed", @order.reload.state
  end

  test "an unpaid order is cancelled and owes nothing" do
    staff_sign_in

    patch staff_cancel_order_url(@order)

    assert_redirected_to staff_board_path
    assert_equal I18n.t("staff.cancelled", id: @order.id), flash[:notice]
    assert_equal "cancelled", @order.reload.state
    assert_nil @order.refund_state
  end

  test "a paid order is cancelled owing a manual refund, and staff are told where" do
    @order.update!(state: "confirmed", payment_state: "captured", payment_method: "stripe")
    staff_sign_in

    patch staff_cancel_order_url(@order)

    assert_equal "cancelled", @order.reload.state
    assert @order.refund_due?
    assert_includes flash[:alert], "Stripe"
    assert_includes flash[:alert], "158 kr"

    get staff_board_url
    refunds = Nokogiri::HTML(response.body).at_css("#refunds_due")
    assert_nil refunds["hidden"]
    assert_includes refunds.text, "##{@order.id}"
  end

  test "marking the refund made takes the order off the list" do
    @order.update!(payment_state: "captured")
    @order.cancel!
    staff_sign_in

    patch staff_refunded_order_url(@order)

    assert_equal "refunded", @order.reload.refund_state
    get staff_board_url
    assert Nokogiri::HTML(response.body).at_css("#refunds_due")["hidden"]
  end

  test "an order already on the grill cannot be cancelled from the board" do
    @order.update!(state: "preparing")
    staff_sign_in

    patch staff_cancel_order_url(@order)

    assert_equal I18n.t("staff.cannot_cancel"), flash[:alert]
    assert_equal "preparing", @order.reload.state
  end

  test "the cancel button sits on placed and confirmed cards only, and asks first" do
    preparing = seed_order!(kitchen: @kitchen, state: "preparing")
    staff_sign_in

    get staff_board_url
    page = Nokogiri::HTML(response.body)

    form = page.at_css(%(#order_card_#{@order.id} form[action="#{staff_cancel_order_path(@order)}"]))
    assert form
    assert_equal I18n.t("staff.cancel_confirm", id: @order.id), form["data-turbo-confirm"]
    assert_nil page.at_css(%(#order_card_#{preparing.id} form[action="#{staff_cancel_order_path(preparing)}"]))
  end

  test "from the board the answer swaps the card out and the refunds list in" do
    @order.update!(payment_state: "captured")
    staff_sign_in

    patch staff_cancel_order_url(@order), as: :turbo_stream

    assert_response :success
    assert_includes response.body, %(<turbo-stream action="remove" target="order_card_#{@order.id}">)
    assert_includes response.body, %(<turbo-stream action="replace" target="refunds_due">)
  end

  test "a payment that lands after the order was cancelled is owed back too" do
    @order.cancel!
    @order.update!(payment_state: "captured")

    assert @order.reload.refund_due?
  end
end
