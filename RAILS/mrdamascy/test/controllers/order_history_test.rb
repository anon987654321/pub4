# frozen_string_literal: true

require "test_helper"

# The signed-in customer's order list and order page.
class OrderHistoryTest < ActionDispatch::IntegrationTest
  setup do
    @user = customer_sign_in
    @order = seed_order!(user: @user)
    @order.update!(placed_at: Time.zone.local(2026, 11, 4, 12, 30))
  end

  test "the order time follows the reader's locale" do
    get orders_url
    assert_includes response.body, "04.11 12:30"

    get orders_url(locale: "en")
    assert_includes response.body, "4 Nov 12:30"

    get order_url(@order, locale: "en")
    assert_includes response.body, "4 Nov 12:30"
  end
end
