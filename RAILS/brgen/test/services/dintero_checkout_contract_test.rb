# frozen_string_literal: true

require "test_helper"

class DinteroCheckoutContractTest < ActiveSupport::TestCase
  setup do
    @keys = %w[
      DINTERO_ACCOUNT_ID DINTERO_CLIENT_ID DINTERO_CLIENT_SECRET DINTERO_PROFILE_ID
      DINTERO_CALLBACK_SECRET DINTERO_CHECKOUT_ENABLED DINTERO_PLATFORM_PAYOUT_DESTINATION_ID
      DINTERO_PLATFORM_COMMISSION_BPS
    ]
    @saved = @keys.to_h { |key| [ key, ENV[key] ] }
    @keys.each { |key| ENV.delete(key) }
  end

  teardown do
    @saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "checkout stays disabled until explicitly enabled" do
    ENV["DINTERO_ACCOUNT_ID"] = "P12345678"
    ENV["DINTERO_CLIENT_ID"] = "client"
    ENV["DINTERO_CLIENT_SECRET"] = "secret"
    ENV["DINTERO_PROFILE_ID"] = "default"
    ENV["DINTERO_CALLBACK_SECRET"] = "callback"

    assert_not Marketplace::Payments::DinteroCheckout.configured?
    ENV["DINTERO_CHECKOUT_ENABLED"] = "1"
    assert Marketplace::Payments::DinteroCheckout.configured?
  end

  test "split leaves the platform fee explicit and sums to the line amount" do
    ENV["DINTERO_PLATFORM_PAYOUT_DESTINATION_ID"] = "platform_123"
    ENV["DINTERO_PLATFORM_COMMISSION_BPS"] = "1000"

    store = Struct.new(:dintero_payout_destination_id, :dintero_payout_destination_status)
      .new("seller_123", "ACTIVE")
    listing = Struct.new(:id, :title, :store, :listing_id)
      .new(7, "Lamp", store, 7)
    order = Struct.new(:listing, :listing_id, :total_cents)
      .new(listing, 7, 1000)

    splits = Marketplace::Payments::DinteroCheckout.send(:split_for, order)
    assert_equal 2, splits.length
    assert_equal 900, splits.sum { |split| split[:amount] if split[:payout_destination_id] == "seller_123" }
    assert_equal 100, splits.sum { |split| split[:amount] if split[:payout_destination_id] == "platform_123" }
    assert_equal 1000, splits.sum { |split| split[:amount] }
  end

  test "inactive seller blocks split creation" do
    store = Struct.new(:dintero_payout_destination_id, :dintero_payout_destination_status)
      .new("seller_123", "PENDING")
    listing = Struct.new(:id, :title, :store).new(7, "Lamp", store)
    order = Struct.new(:listing, :listing_id, :total_cents).new(listing, 7, 1000)

    assert_raises(Marketplace::Payments::DinteroCheckout::SellerNotReady) do
      Marketplace::Payments::DinteroCheckout.send(:split_for, order)
    end
  end
end
