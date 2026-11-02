# frozen_string_literal: true

require "test_helper"

class WoltDriveClientTest < ActiveSupport::TestCase
  setup do
    @kitchen = seed_kitchen!
    @zone = seed_zone!
    @order = Order.create!(
      user: seed_customer!,
      kitchen: @kitchen,
      state: "ready",
      delivery_mode: "delivery",
      address: "Nygårdsgaten 12",
      postcode: "5015",
      phone: "90000004",
      subtotal_ore: 25800,
      delivery_fee_ore: 2900,
      total_ore: 28700,
      eta_minutes: 30,
      tracking_token: "tok-wolt-1",
      placed_at: Time.current
    )
  end

  # Mock mode is the default (ENV["WOLT_DRIVE_MOCK"] != "0") — the same
  # contract as VippsClient: the demo flow must work with zero credentials.
  test "mock request assigns a courier and stores the delivery on the order" do
    result = WoltDriveClient.request_delivery(order: @order)

    assert_equal "mock-wolt-tok-wolt-1", result[:id]
    assert_equal "courier_assigned", result[:status]
    assert_equal "Bergen Bud", result[:courier]
    assert_equal result[:id], @order.reload.external_delivery_id
    assert_equal result[:tracking_url], @order.external_delivery_url
    assert result[:tracking_url].present?
  end

  test "mock request is idempotent per order via the controller guard" do
    WoltDriveClient.request_delivery(order: @order)
    first_id = @order.reload.external_delivery_id
    result = WoltDriveClient.request_delivery(order: @order)

    # The client itself is stateless; double-dispatch prevention lives in
    # Staff::BoardController#dispatch_wolt_safely, but a re-request still
    # resolves to the same stable mock id for the same tracking token.
    assert_equal first_id, result[:id]
  end

  test "delivery_status in mock mode reports created without network" do
    assert_equal({ status: "created", courier: nil }, WoltDriveClient.delivery_status(delivery_id: "x"))
  end

  # Step 1 of the documented Wolt Drive flow — quote before dispatch. Mock
  # mode answers with a plausible Bergen promise and zero credentials.
  test "mock shipment promise quotes availability, fee and eta" do
    quote = WoltDriveClient.shipment_promise(order: @order)

    assert_equal true, quote[:available]
    assert_equal 4900, quote[:fee_ore]
    assert_equal 35, quote[:eta_minutes]
  end

  test "real mode raises NotAvailable without credentials" do
    ENV["WOLT_DRIVE_MOCK"] = "0"
    ENV.delete("WOLT_DRIVE_API_TOKEN")

    error = assert_raises(WoltDriveClient::NotAvailable) do
      WoltDriveClient.request_delivery(order: @order)
    end
    assert_match(/WOLT_DRIVE_API_TOKEN/, error.message)
  ensure
    ENV.delete("WOLT_DRIVE_MOCK")
  end
end
