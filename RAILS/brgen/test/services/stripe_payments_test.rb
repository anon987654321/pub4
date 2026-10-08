# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class StripePaymentsTest < ActiveSupport::TestCase
  KEYS = %w[STRIPE_SECRET_KEY STRIPE_TEST_MODE].freeze

  setup { @saved = KEYS.to_h { |k| [ k, ENV[k] ] }; KEYS.each { |k| ENV.delete(k) } }
  teardown { @saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v } }

  def prod(&block)
    original = Rails.env
    Rails.instance_variable_set(:@_env, ActiveSupport::EnvironmentInquirer.new("production"))
    block.call
  ensure
    Rails.instance_variable_set(:@_env, original)
  end

  test "unconfigured is unconfigured — no key fakes readiness" do
    assert_not Marketplace::Payments::StripeCheckout.configured?
    assert_raises(Marketplace::Payments::NotConfigured) { Marketplace::Payments::StripeCheckout.ensure! }
    assert_raises(Marketplace::Payments::NotConfigured) do
      Marketplace::Payments::StripeRefund.submit!(
        order: Struct.new(:id, :payment_reference, keyword_init: true).new(id: 1, payment_reference: "pi_x")
      )
    end
  end

  test "production refuses a test key unless test mode says so out loud" do
    ENV["STRIPE_SECRET_KEY"] = "sk_test_not_live"
    prod do
      assert_raises(Marketplace::Payments::NotConfigured) { Marketplace::Payments::StripeCheckout.ensure! }
      ENV["STRIPE_TEST_MODE"] = "1"
      assert_nothing_raised { Marketplace::Payments::StripeCheckout.ensure! }
    end
  end

  test "refund POSTs an idempotency key against the payment intent" do
    ENV["STRIPE_SECRET_KEY"] = "sk_test_local"
    seen = nil
    Marketplace::Payments::StripeClient.stub(:post, ->(url, form, idempotency_key:) {
      seen = { url:, form:, idempotency_key: }
      { "id" => "re_1" }
    }) do
      Marketplace::Payments::StripeClient.stub(:get, ->(_url) { { "payment_intent" => "pi_abc" } }) do
        id = Marketplace::Payments::StripeRefund.submit!(
          order: Struct.new(:id, :payment_reference, keyword_init: true)
                      .new(id: 42, payment_reference: "cs_test_session")
        )
        assert_equal "re_1", id
      end
    end
    assert_equal "https://api.stripe.com/v1/refunds", seen[:url]
    assert_equal "pi_abc", seen[:form]["payment_intent"]
    assert_equal "marketplace-refund-42", seen[:idempotency_key]
  end

  test "transfer refuses a destination that is not a Connect account" do
    ENV["STRIPE_SECRET_KEY"] = "sk_test_local"
    relation = Object.new
    def relation.pick(*) = "cus_not_connect"
    Marketplace::Store.stub(:where, ->(*) { relation }) do
      payout = Struct.new(:id, :store_id, :amount_cents, :currency, :order_id, keyword_init: true)
                    .new(id: 1, store_id: 7, amount_cents: 1000, currency: "NOK", order_id: 9)
      assert_raises(Marketplace::Payments::NotConfigured) do
        Marketplace::Payments::StripeTransfer.submit!(payout: payout)
      end
    end
  end
end
