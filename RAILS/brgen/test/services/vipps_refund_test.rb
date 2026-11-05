# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# A Vipps buyer's received return gets their money back: captured money is
# refunded, a reservation is cancelled, and every write carries the return's
# idempotency key. Nothing here reaches Vipps; call_api is stubbed.
class VippsRefundTest < ActiveSupport::TestCase
  KEYS = %w[VIPPS_EPAYMENT_CLIENT_ID VIPPS_EPAYMENT_CLIENT_SECRET VIPPS_MSN VIPPS_SUBSCRIPTION_KEY].freeze
  Order = Struct.new(:payment_reference, :total_cents, :payment_currency, keyword_init: true)

  setup do
    @saved = KEYS.to_h { [ _1, ENV[_1] ] }
    KEYS.each { ENV[_1] = "test-#{_1.downcase}" }
  end

  teardown { @saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v } }

  def order = Order.new(payment_reference: "brgen-order-7-ab12", total_cents: 25_000, payment_currency: "NOK")

  def recording(payment)
    calls = []
    api = lambda do |verb, path, idempotency_key: nil, body: nil|
      calls << { verb:, path:, idempotency_key:, body: }
      verb == :get ? payment : { "pspReference" => "psp-1" }
    end
    [ calls, api ]
  end

  test "captured money is refunded with the return's idempotency key" do
    calls, api = recording("aggregate" => { "capturedAmount" => { "value" => 25_000 }, "refundedAmount" => { "value" => 0 } })
    Marketplace::Payments::VippsRefund.stub(:call_api, api) do
      assert_equal "psp-1", Marketplace::Payments::VippsRefund.submit!(order: order, idempotency_key: "brgen-return-3-refund")
    end

    write = calls.last
    assert_equal :post, write[:verb]
    assert_equal "brgen-order-7-ab12/refund", write[:path]
    assert_equal "brgen-return-3-refund", write[:idempotency_key]
    assert_equal({ currency: "NOK", value: 25_000 }, write[:body][:modificationAmount])
  end

  test "a reservation that was never captured is cancelled, not refunded" do
    calls, api = recording("aggregate" => { "capturedAmount" => { "value" => 0 } })
    Marketplace::Payments::VippsRefund.stub(:call_api, api) do
      Marketplace::Payments::VippsRefund.submit!(order: order, idempotency_key: "brgen-return-3-refund")
    end

    assert_equal "brgen-order-7-ab12/cancel", calls.last[:path]
    assert_equal "brgen-return-3-refund-cancel", calls.last[:idempotency_key]
  end

  test "money Vipps already refunded is not sent again" do
    calls, api = recording("aggregate" => { "capturedAmount" => { "value" => 25_000 }, "refundedAmount" => { "value" => 25_000 } })
    Marketplace::Payments::VippsRefund.stub(:call_api, api) do
      Marketplace::Payments::VippsRefund.submit!(order: order, idempotency_key: "k")
    end

    assert_equal [ :get ], calls.map { _1[:verb] }
  end

  test "without Vipps keys nothing is sent" do
    KEYS.each { ENV.delete(_1) }
    assert_raises(Marketplace::Payments::NotConfigured) do
      Marketplace::Payments::VippsRefund.submit!(order: order, idempotency_key: "k")
    end
  end

  test "a received return on a Vipps order is refunded through Vipps" do
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    seller = User.create!(email_address: "vr_seller_#{SecureRandom.hex(3)}@brgen.no", password: "password123")
    buyer = User.create!(email_address: "vr_buyer_#{SecureRandom.hex(3)}@brgen.no", password: "password123")
    category = Marketplace::Category.create!(name: "Sko", slug: "vr-#{SecureRandom.hex(4)}")
    store = Marketplace::Store.create!(owner: seller, name: "Butikk #{SecureRandom.hex(2)}", slug: "vr-#{SecureRandom.hex(4)}")
    listing = Marketplace::Listing.create!(user: seller, category:, store:, title: "Sko", price_cents: 25_000, stock: 2)
    paid = listing.orders.create!(buyer:, price_cents: 25_000, quantity: 1)
    paid.update!(payment_status: "paid", status: "paid", payment_provider: "vipps", payment_reference: "brgen-order-#{paid.id}-ff")
    paid.mark_delivered!
    sent_back = paid.returns.create!(reason: "For store")

    keys = []
    Marketplace::Payments::VippsRefund.stub(:submit!, ->(order:, idempotency_key:) { keys << idempotency_key; "psp-9" }) do
      sent_back.receive!(by: seller)
    end

    assert_predicate sent_back.reload, :refunded?
    assert_equal "psp-9", sent_back.refund_reference
    assert_equal [ "brgen-return-#{sent_back.id}-refund" ], keys
    assert_equal "refunded", paid.reload.payment_status
  ensure
    ActsAsTenant.current_tenant = nil
  end
end
