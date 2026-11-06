# frozen_string_literal: true

require "test_helper"

# The mission, held as a test (README: "Foodora vs Mr. Damascy — the step
# math" and APP_SPEC §5): the kitchen owns the whole order. No marketplace
# middleman (Foodora, FoodBooking) is integrated anywhere, and Wolt Drive is
# a staff-initiated overflow lane that no part of the order lifecycle needs —
# the kitchen's own couriers carry every bag unless a human presses the
# overflow button. These tests keep all three claims true.
class PlatformIndependenceTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = seed_kitchen!
    @category = seed_category!(@kitchen)
    @item = seed_item!(@category)
    seed_zone!(min_basket_ore: 10_000)  # admits the single-wrap happy path
    @user = customer_sign_in
  end

  teardown do
    sc = WoltDriveClient.singleton_class
    if sc.method_defined?(:orig_request_delivery)
      sc.send(:alias_method, :request_delivery, :orig_request_delivery)
      sc.send(:remove_method, :orig_request_delivery)
    end
  end

  test "no marketplace middleman is wired into the codebase" do
    # Foodora's Restaurant Integration API and FoodBooking's ordering API put
    # a commission-taking marketplace back between the kitchen and the
    # customer. Prose that says "no Foodora" is mission copy and stays; any
    # platform HOST or client wiring must never appear in app code.
    offenders = (Dir.glob("app/**/*.rb") + [ "config/routes.rb" ])
      .select { |path| File.read(path) =~ /foodora\.|foodbooking\.|deliveryhero|vendor\.foodora/i }
    assert_empty offenders, "a marketplace middleman crept into app code: #{offenders.inspect}"
  end

  test "wolt drive is reachable only from the staff board's manual dispatch" do
    # No job, no recurring task, no model callback may book a courier on its
    # own — the overflow lane is a human decision on the kitchen board.
    callers = Dir.glob("app/**/*.rb").select do |path|
      File.read(path).include?("WoltDriveClient") &&
        !path.end_with?("services/wolt_drive_client.rb")
    end
    assert_equal [ "app/controllers/staff/board_controller.rb" ], callers.sort
  end

  test "the whole order lifecycle completes with the courier platforms refusing" do
    # Make any Wolt booking explode. If the lifecycle below ever needs one,
    # the test fails loudly — own couriers are the only required lane.
    sc = WoltDriveClient.singleton_class
    sc.send(:alias_method, :orig_request_delivery, :request_delivery)
    sc.send(:define_method, :request_delivery) do |**|
      raise WoltDriveClient::NotAvailable, "platforms refuse — the kitchen must not care"
    end

    # 1) the customer orders and pays (mock Vipps — the only payment rail)
    post add_item_cart_url, params: { menu_item_id: @item.id, quantity: 1,
                                      option_ids: [], note: "" }
    assert_includes [ 200, 302, 303 ], response.status
    post checkout_url, params: { order: { address: "Nygårdsgaten 12", postcode: "5004",
                                          phone: "90000004", delivery_mode: "delivery" } }
    order = Order.order(:id).last
    assert_not_nil order, "checkout must build the order"
    assert_redirected_to order.vipps_url
    patch vipps_mock_approve_url, params: { token: order.tracking_token }
    assert_redirected_to track_path(order.tracking_token)
    assert_equal "captured", order.reload.payment_state
    assert_equal "confirmed", order.reload.state

    # 2) the kitchen's own staff advance the order to ready
    staff_sign_in
    3.times do
      patch staff_advance_order_url(order), params: {}
      assert_redirected_to staff_board_path
      order.reload
    end
    assert_equal "ready", order.state

    # 3) the kitchen's own courier carries the bag, no platform in sight
    courier_sign_in
    patch courier_pickup_order_url(order), params: {}
    assert_equal "picked_up", order.reload.state
    patch courier_deliver_order_url(order), params: {}
    assert_equal "delivered", order.reload.state

    # 4) loyalty stays ours too: the stamp is awarded by the kitchen
    assert_equal 1, LoyaltyStamp.where(user: @user).count
  end
end
