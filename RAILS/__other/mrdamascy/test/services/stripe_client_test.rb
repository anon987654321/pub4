# frozen_string_literal: true

require "test_helper"

# StripeClient contract — the second payment lane (operator-mandated), same
# honesty rules as VippsClient:
#
#   Mock mode (default): init never raises, points at /stripe/mock, marks the
#   payment authorised. sync_payment! is a no-op there — the mock approve
#   action owns capture.
#
#   Real mode (STRIPE_MOCK=0): documented Checkout Sessions calls, form-encoded.
#   The HTTP core (perform_request) is stubbed with path-keyed canned responses
#   (StripeHttpStubbing); everything above it — auth header, payload shape,
#   state mapping, capture semantics — runs for real. Missing ENV raises
#   NotAvailable before any HTTP happens.
class StripeClientTest < ActiveSupport::TestCase
  setup do
    @kitchen = seed_kitchen!
    @order = seed_order!(token: "tok-stripe-1")
    @order.update!(total_ore: 15800, vipps_order_id: nil, vipps_url: nil,
                   payment_method: "stripe")
  end

  teardown do
    stripe_restore_http!
  end

  # --- Mock mode (the demo/dev contract) --------------------------------------

  test "mock init fills session id, url and authorised without network" do
    assert StripeClient.mock_mode?

    assert StripeClient.init_payment(order: @order)
    assert_equal "mock-stripe-tok-stripe-1", @order.vipps_order_id
    assert_match %r{/stripe/mock\?token=tok-stripe-1\z}, @order.vipps_url
    assert_equal "authorised", @order.payment_state
  end

  test "mock sync_payment! is a no-op — the mock approve action owns capture" do
    @order.update!(payment_state: "authorised", vipps_order_id: "mock-stripe-tok-stripe-1")

    StripeClient.sync_payment!(order: @order)

    assert_equal "authorised", @order.reload.payment_state
  end

  # --- Real mode: wiring gaps fail loudly, before any HTTP --------------------

  test "real mode raises NotAvailable without credentials" do
    ENV["STRIPE_MOCK"] = "0"
    ENV.delete("STRIPE_SECRET_KEY")

    error = assert_raises(StripeClient::NotAvailable) do
      StripeClient.init_payment(order: @order)
    end
    assert_nil @order.reload.vipps_url, "a failed init must not leave a fake payment url"
  end

  # --- Real mode: the documented Checkout Sessions flow ------------------------

  test "real init creates the session, stores id and hosted url" do
    stripe_real_mode!
    assert StripeClient.init_payment(order: @order)

    init = stripe_call_for("/v1/checkout/sessions")
    params = init[:body_parsed]
    assert_equal "payment", params["mode"]
    assert_equal "mrdamascy-tok-stripe-1", params["client_reference_id"]
    assert_equal "tok-stripe-1", params["metadata[tracking_token]"]
    assert_equal "nok", params["line_items[0][price_data][currency]"]
    assert_equal "15800", params["line_items[0][price_data][unit_amount]"],
                 "checkout must post the exact øre total — no rounding anywhere"
    assert_equal "1", params["line_items[0][quantity]"]
    assert_match %r{/track/tok-stripe-1\z}, params["success_url"]
    assert_equal "Bearer sk_test_stripe", init[:headers]["Authorization"]

    @order.reload
    assert_equal "cs_test_123", @order.vipps_order_id
    assert_equal "https://checkout.stripe.com/c/pay/cs_test_123", @order.vipps_url
    assert_equal "pending", @order.payment_state,
                 "real money is reserved only when the customer completes Checkout"
  end

  test "sync marks the order captured and confirmed when Stripe reports paid" do
    @order.update!(payment_state: "authorised", vipps_order_id: "cs_test_123")
    stripe_real_mode!

    StripeClient.sync_payment!(order: @order)

    @order.reload
    assert_equal "captured", @order.payment_state
    assert_equal "confirmed", @order.state
  end

  test "sync never rewinds an order the kitchen already advanced" do
    @order.update!(payment_state: "authorised", vipps_order_id: "cs_test_123",
                   state: "preparing")
    stripe_real_mode!

    StripeClient.sync_payment!(order: @order)

    @order.reload
    assert_equal "captured", @order.payment_state
    assert_equal "preparing", @order.state, "capture must not rewind the kitchen"
  end

  test "sync marks an expired session failed without cooking" do
    @order.update!(payment_state: "authorised", vipps_order_id: "cs_test_123")
    stripe_real_mode!(remote_status: "expired")

    StripeClient.sync_payment!(order: @order)

    assert_equal "failed", @order.reload.payment_state
  end

  test "sync swallows transport errors — the poll must never 500 the page" do
    @order.update!(payment_state: "authorised", vipps_order_id: "cs_test_123")

    ENV["STRIPE_MOCK"] = "0"
    ENV["STRIPE_SECRET_KEY"] = "sk_test_stripe"
    sc = StripeClient.singleton_class
    sc.send(:alias_method, :orig_perform_request, :perform_request)
    sc.send(:define_method, :perform_request) do |*_args|
      raise StripeClient::NotAvailable, "Stripe API GET failed: HTTP 503"
    end

    assert_nothing_raised do
      StripeClient.sync_payment!(order: @order)
    end
    assert_equal "authorised", @order.reload.payment_state
  end

  test "sync on an already-captured order still converges" do
    @order.update!(payment_state: "captured", vipps_order_id: "cs_test_123")
    stripe_real_mode!

    assert_nothing_raised do
      StripeClient.sync_payment!(order: @order)
    end
    assert_equal "captured", @order.reload.payment_state
  end

  # --- Webhook signature --------------------------------------------------------

  test "verify_signature! accepts a correctly signed payload" do
    ENV["STRIPE_WEBHOOK_SECRET"] = "whsec_test"
    payload = '{"id":"evt_1","type":"checkout.session.completed"}'

    assert StripeClient.verify_signature!(
      payload: payload,
      header: stripe_signature_for(payload, secret: "whsec_test"),
      secret: "whsec_test"
    )
  end

  test "verify_signature! rejects tampered payloads, wrong secrets, stale timestamps" do
    ENV["STRIPE_WEBHOOK_SECRET"] = "whsec_test"
    payload = '{"id":"evt_1","type":"checkout.session.completed"}'

    assert_raises(StripeClient::NotAvailable) do
      StripeClient.verify_signature!(
        payload: payload, header: stripe_signature_for(payload, secret: "whsec_test"),
        secret: "whsec_other"
      )
    end

    assert_raises(StripeClient::NotAvailable) do
      StripeClient.verify_signature!(
        payload: payload + " ", header: stripe_signature_for(payload, secret: "whsec_test"),
        secret: "whsec_test"
      )
    end

    assert_raises(StripeClient::NotAvailable) do
      StripeClient.verify_signature!(
        payload: payload,
        header: stripe_signature_for(payload, secret: "whsec_test",
                                     timestamp: 10.minutes.ago.to_i),
        secret: "whsec_test"
      )
    end

    assert_raises(StripeClient::NotAvailable) do
      StripeClient.verify_signature!(payload: payload, header: "", secret: "whsec_test")
    end
  end

  test "verify_signature! refuses to run without a configured secret" do
    ENV.delete("STRIPE_WEBHOOK_SECRET")

    assert_raises(StripeClient::NotAvailable) do
      StripeClient.verify_signature!(payload: "{}", header: "t=1,v1=abc", secret: "")
    end
  end
end
