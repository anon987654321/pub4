# frozen_string_literal: true

require "test_helper"

class DinteroCheckoutTest < ActiveSupport::TestCase
  Store = Struct.new(
    :dintero_payout_destination_id,
    :dintero_payout_destination_status,
    keyword_init: true
  )

  Listing = Struct.new(:id, :title, :store, keyword_init: true)

  FakeOrder = Struct.new(
    :id, :listing, :quantity, :total_cents, :payment_currency, :payment_description,
    :payment_reference, :payment_provider, :payment_status, :dintero_order_id, :dintero_split_json,
    :dintero_session_id, :dintero_transaction_id, keyword_init: true
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
      DINTERO_PROFILE_ID DINTERO_CALLBACK_SECRET DINTERO_HOOK_SECRET DINTERO_CHECKOUT_ENABLED
      DINTERO_PLATFORM_PAYOUT_DESTINATION_ID DINTERO_PLATFORM_COMMISSION_BPS
    ].to_h { |key| [ key, ENV[key] ] }
    ENV["DINTERO_ACCOUNT_ID"] = "T12345678"
    ENV["DINTERO_CLIENT_ID"] = "client"
    ENV["DINTERO_CLIENT_SECRET"] = "secret"
    ENV["DINTERO_PROFILE_ID"] = "profile"
    ENV["DINTERO_CHECKOUT_ENABLED"] = "1"
    ENV["DINTERO_CALLBACK_SECRET"] = "callback"
    ENV["DINTERO_HOOK_SECRET"] = "hook"
    ENV["DINTERO_PLATFORM_PAYOUT_DESTINATION_ID"] = "platform-1"
    ENV["DINTERO_PLATFORM_COMMISSION_BPS"] = "500"
  end

  teardown do
    @saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def order(store:, dintero_order_id: nil)
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
      dintero_order_id: dintero_order_id,
      dintero_split_json: nil,
      dintero_session_id: nil,
      dintero_transaction_id: nil
    )
  end

  test "a configured seller completes a Dintero draft before creating its session" do
    seller = Store.new(
      dintero_payout_destination_id: "seller-1",
      dintero_payout_destination_status: "ACTIVE"
    )
    calls = []
    Marketplace::Payments::DinteroClient.stub(:post, lambda { |path, payload, **options|
      calls << { method: :post, path:, payload:, options: }
      case path
      when %r{/shopping/draft_orders\z}
        { "id" => "draft-1" }
      when %r{/shopping/orders/order-1/sessions\z}
        { "id" => "session-1", "url" => "https://checkout.dintero.com/v1/view/session-1/" }
      end
    }) do
      Marketplace::Payments::DinteroClient.stub(:put, ->(path, **options) {
        calls << { method: :put, path:, options: }
        { "order_id" => "order-1" }
      }) do
        url = Marketplace::Payments::DinteroCheckout.start!(
          order: order(store: seller),
          return_url: "https://markedsplass.brgen.no/checkout",
          callback_url: "https://markedsplass.brgen.no/webhooks/dintero/callback"
        )
        assert_equal "https://checkout.dintero.com/v1/view/session-1/", url
      end
    end

    draft = calls[0]
    complete = calls[1]
    session = calls[2]

    assert_equal :post, draft[:method]
    assert_match(%r{/shopping/draft_orders\z}, draft[:path])
    assert_equal false, draft[:payload][:options][:split_draft]
    assert_nil draft[:payload][:order][:items].first[:store]
    assert_equal 10_000, draft[:payload][:order][:items].first[:amount]
    assert_nil draft[:payload][:order][:items].first[:unit_price]
    assert_nil draft[:payload][:order][:items].first[:gross_amount]
    assert_equal :put, complete[:method]
    assert_match(%r{/shopping/draft_orders/draft-1/complete\z}, complete[:path])

    assert_equal :post, session[:method]
    assert_match(%r{/shopping/orders/order-1/sessions\z}, session[:path])
    assert_equal 42, session[:payload][:items].first[:line_id]
    assert_equal 10_000, session[:payload][:items].first[:amount]
    assert_equal [
      { payout_destination_id: "seller-1", amount: 9_500 },
      { payout_destination_id: "platform-1", amount: 500 }
    ], session[:payload][:items].first[:splits]
    assert_equal(
      { type: "proportional", destinations: [ "platform-1" ] },
      session[:payload][:fee_split]
    )
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


  test "refund reuses the persisted split contract" do
    seller = Store.new(
      dintero_payout_destination_id: "seller-1",
      dintero_payout_destination_status: "ACTIVE"
    )
    payable = order(store: seller, dintero_order_id: "order-1")
    payable.payment_provider = "dintero"
    payable.payment_status = "paid"
    payable.payment_reference = "brgen-dintero-order-42"
    payable.dintero_split_json = JSON.generate(
      splits: [
        { payout_destination_id: "seller-1", amount: 9_500 },
        { payout_destination_id: "platform-1", amount: 500 }
      ],
      fee_split: { type: "proportional", destinations: [ "platform-1" ] }
    )
    ENV["DINTERO_PLATFORM_COMMISSION_BPS"] = "2000"

    seen = nil
    Marketplace::Payments::DinteroClient.stub(:post, ->(path, payload, **options) {
      seen = { path:, payload:, options: }
      {}
    }) do
      Marketplace::Payments::DinteroCheckout.refund!(order: payable)
    end

    assert_equal [
      { payout_destination_id: "seller-1", amount: 9_500 },
      { payout_destination_id: "platform-1", amount: 500 }
    ], seen[:payload][:items].first[:splits]
    assert_equal "proportional", seen[:payload][:fee_split][:type]
    assert_equal "platform-1", seen[:payload][:fee_split][:destinations].first
  end

  test "refund sends Dintero refund and leaves local order paid until webhook confirmation" do
    seller = Store.new(
      dintero_payout_destination_id: "seller-1",
      dintero_payout_destination_status: "ACTIVE"
    )
    payable = order(store: seller, dintero_order_id: "order-1")
    payable.payment_provider = "dintero"
    payable.payment_status = "paid"
    payable.payment_reference = "brgen-dintero-order-42"
    payable.dintero_split_json = JSON.generate(
      splits: [
        { payout_destination_id: "seller-1", amount: 9_500 },
        { payout_destination_id: "platform-1", amount: 500 }
      ],
      fee_split: { type: "proportional", destinations: [ "platform-1" ] }
    )

    seen = nil
    Marketplace::Payments::DinteroClient.stub(:post, ->(path, payload, **options) {
      seen = { path:, payload:, options: }
      {}
    }) do
      Marketplace::Payments::DinteroCheckout.refund!(order: payable)
    end

    assert_equal "/v1/accounts/T12345678/shopping/orders/order-1/refunds", seen[:path]
    assert_equal 10_000, seen[:payload][:items].first[:amount]
    assert_equal "brgen-refund-order-42", seen[:options][:idempotency_key]
    assert_equal(
      { type: "proportional", destinations: [ "platform-1" ] },
      seen[:payload][:fee_split]
    )
    assert_equal "paid", payable.payment_status
  end


  test "capture refuses when seller payout destination changes after authorization" do
    seller = Store.new(
      dintero_payout_destination_id: "seller-2",
      dintero_payout_destination_status: "ACTIVE"
    )
    payable = order(store: seller, dintero_order_id: "order-1")
    payable.payment_provider = "dintero"
    payable.payment_status = "authorized"
    payable.payment_reference = "brgen-dintero-order-42"
    payable.dintero_transaction_id = "transaction-1"
    payable.dintero_split_json = JSON.generate(
      splits: [
        { payout_destination_id: "seller-1", amount: 9_500 },
        { payout_destination_id: "platform-1", amount: 500 }
      ],
      fee_split: { type: "proportional", destinations: [ "platform-1" ] }
    )

    assert_raises(Marketplace::Payments::DinteroCheckout::SellerNotReady) do
      Marketplace::Payments::DinteroCheckout.capture!(order: payable)
    end
  end

  test "capture sends the operation and leaves the local order authorized until webhook confirmation" do
    seller = Store.new(
      dintero_payout_destination_id: "seller-1",
      dintero_payout_destination_status: "ACTIVE"
    )
    payable = order(store: seller, dintero_order_id: "order-1")
    payable.payment_provider = "dintero"
    payable.payment_status = "authorized"
    payable.payment_reference = "brgen-dintero-order-42"
    payable.dintero_transaction_id = "transaction-1"
    payable.dintero_split_json = JSON.generate(
      splits: [
        { payout_destination_id: "seller-1", amount: 9_500 },
        { payout_destination_id: "platform-1", amount: 500 }
      ],
      fee_split: { type: "proportional", destinations: [ "platform-1" ] }
    )

    seen = nil
    Marketplace::Payments::DinteroClient.stub(:post, ->(path, payload, **options) {
      seen = { path:, payload:, options: }
      {}
    }) do
      Marketplace::Payments::DinteroCheckout.capture!(order: payable)
    end

    assert_equal "/v1/accounts/T12345678/shopping/orders/order-1/captures", seen[:path]
    assert_equal 10_000, seen[:payload][:items].first[:amount]
    assert_equal "brgen-capture-order-42", seen[:options][:idempotency_key]
    assert_equal(
      { type: "proportional", destinations: [ "platform-1" ] },
      seen[:payload][:fee_split]
    )
    assert_equal "authorized", payable.payment_status
  end
end
