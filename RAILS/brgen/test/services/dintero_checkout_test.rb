# frozen_string_literal: true

require "test_helper"

class DinteroCheckoutTest < ActiveSupport::TestCase
  Store = Struct.new(:dintero_payout_destination_id, :dintero_payout_destination_status, keyword_init: true)
  Listing = Struct.new(:id, :title, :store, keyword_init: true)
  FakeOrder = Struct.new(
    :id, :listing, :quantity, :total_cents, :payment_currency, :payment_description,
    :payment_reference, :payment_provider, :payment_status, :dintero_session_id,
    :dintero_transaction_id, keyword_init: true
  ) do
    def startable? = true

    def update_columns(values)
      values.each { |key, value| public_send("#{key}=", value) }
    end

    def update!(values)
      update_columns(values)
    end

    def mark_paid!(reference:)
      self.payment_reference = reference
      self.payment_status = "paid"
    end
  end

  setup do
    @saved = %w[
      DINTERO_ACCOUNT_ID DINTERO_CLIENT_ID DINTERO_CLIENT_SECRET
      DINTERO_PROFILE_ID DINTERO_CALLBACK_SECRET DINTERO_HOOK_SECRET
      DINTERO_PLATFORM_PAYOUT_DESTINATION_ID DINTERO_PLATFORM_COMMISSION_BPS
    ].to_h { |key| [ key, ENV[key] ] }
    ENV["DINTERO_ACCOUNT_ID"] = "T12345678"
    ENV["DINTERO_CLIENT_ID"] = "client"
    ENV["DINTERO_CLIENT_SECRET"] = "secret"
    ENV["DINTERO_PROFILE_ID"] = "profile"
    ENV["DINTERO_CALLBACK_SECRET"] = "callback"
    ENV["DINTERO_HOOK_SECRET"] = "hook"
    ENV.delete("DINTERO_PLATFORM_PAYOUT_DESTINATION_ID")
    ENV["DINTERO_PLATFORM_COMMISSION_BPS"] = "500"
  end

  teardown do
    @saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def order(store:)
    FakeOrder.new(
      id: 42,
      listing: Listing.new(id: 7, title: "Desk", store:),
      quantity: 1,
      total_cents: 10_000,
      payment_currency: "NOK",
      payment_description: "Desk",
      payment_reference: nil,
      payment_provider: nil,
      payment_status: "unpaid",
      dintero_session_id: nil,
      dintero_transaction_id: nil
    )
  end

  test "a configured seller gets a split session with an explicit platform fee" do
    ENV["DINTERO_PLATFORM_PAYOUT_DESTINATION_ID"] = "platform-1"
    seller = Store.new(
      dintero_payout_destination_id: "seller-1",
      dintero_payout_destination_status: "ACTIVE"
    )
    seen = nil
    result = { "id" => "session-1", "url" => "https://checkout.dintero.com/v1/view/session-1/" }

    Marketplace::Payments::DinteroClient.stub(:post, ->(path, payload, **options) {
      seen = { path:, payload:, options: }
      result
    }) do
      url = Marketplace::Payments::DinteroCheckout.start!(
        order: order(store: seller),
        return_url: "https://markedsplass.brgen.no/checkout",
        callback_url: "https://markedsplass.brgen.no/webhooks/dintero/callback"
      )
      assert_equal result["url"], url
    end

    item = seen[:payload][:order][:items].first
    assert_equal [
      { payout_destination_id: "seller-1", amount: 9_500 },
      { payout_destination_id: "platform-1", amount: 500 }
    ], item[:splits]
    assert_equal({ type: "proportional", destinations: [ "platform-1" ] }, item[:fee_split])
    assert_equal "dintero", seen[:payload][:order][:merchant_reference].to_s.split("-")[1]
  end

  test "an unapproved seller is rejected before the Dintero request" do
    seller = Store.new(
      dintero_payout_destination_id: "seller-1",
      dintero_payout_destination_status: "WAITING_FOR_SIGNATURE"
    )
    assert_raises(Marketplace::Payments::DinteroCheckout::SellerNotReady) do
      Marketplace::Payments::DinteroCheckout.ensure_sellers_ready!([ order(store: seller) ])
    end
  end

  test "capture uses the recorded transaction and the same split contract" do
    ENV["DINTERO_PLATFORM_PAYOUT_DESTINATION_ID"] = "platform-1"
    seller = Store.new(
      dintero_payout_destination_id: "seller-1",
      dintero_payout_destination_status: "ACTIVE"
    )
    payable = order(store: seller)
    payable.payment_provider = "dintero"
    payable.payment_status = "authorized"
    payable.payment_reference = "brgen-dintero-order-42"
    payable.dintero_transaction_id = "transaction-1"
    seen = nil

    Marketplace::Payments::DinteroClient.stub(:post, ->(path, payload, **options) {
      seen = { path:, payload:, options: }
      {}
    }) do
      Marketplace::Payments::DinteroCheckout.capture!(order: payable)
    end

    assert_equal "/v1/transactions/transaction-1/capture", seen[:path]
    assert_equal 10_000, seen[:payload][:amount]
    assert_equal "brgen-capture-order-42", seen[:options][:idempotency_key]
    assert_equal "paid", payable.payment_status
  end
end
