# frozen_string_literal: true

require "test_helper"

# The courier's run: who may open it, the two moves, and what a stop shows.
class CourierRunsTest < ActionDispatch::IntegrationTest
  setup do
    @customer = seed_customer!
    @ready = seed_order!(user: @customer, state: "ready")
    @on_way = seed_order!(user: @customer, state: "picked_up")
  end

  test "only couriers open the run or move its orders" do
    get courier_runs_url
    assert_redirected_to root_path

    customer_sign_in(phone: "90000011")
    patch courier_pickup_order_url(@ready)
    assert_redirected_to root_path
    assert_equal "ready", @ready.reload.state
  end

  test "a courier picks up a ready order" do
    courier_sign_in
    patch courier_pickup_order_url(@ready)

    assert_redirected_to courier_runs_path
    assert_equal "picked_up", @ready.reload.state
  end

  test "delivering awards exactly one stamp, and a second tap changes nothing" do
    courier_sign_in
    2.times { patch courier_deliver_order_url(@on_way) }

    assert_equal "delivered", @on_way.reload.state
    assert_equal 1, LoyaltyStamp.where(order: @on_way).count
    assert_equal I18n.t("courier.cannot_deliver"), flash[:alert]
  end

  test "a stop opens the address in maps, dials the phone and asks before Levert" do
    courier_sign_in
    get courier_runs_url
    page = Nokogiri::HTML(response.body)

    assert page.at_css(%(.run-address a[href^="https://www.google.com/maps/search/?api=1&query=Ny"]))
    assert page.at_css(%(.run-phone a[href="tel:90000004"]))
    confirm = page.at_css(%(form[action="#{courier_deliver_order_path(@on_way)}"]))["data-turbo-confirm"]
    assert_equal I18n.t("courier.deliver_confirm", id: @on_way.id), confirm
  end
end
