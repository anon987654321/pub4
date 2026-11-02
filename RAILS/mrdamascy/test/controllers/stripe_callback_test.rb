# frozen_string_literal: true

require "test_helper"

# The real Stripe webhook (POST /stripe/callback): Stripe signs the body with
# HMAC-SHA256 and carries t=/v1= pairs in the Stripe-Signature header.
# Contract here: unsigned/wrongly-signed/stale → 400, verified
# checkout.session.completed drives sync_payment! (captured + confirmed),
# replays converge, garbage JSON → 400, unknown sessions answer politely.
class StripeCallbackTest < ActionDispatch::IntegrationTest
  setup do
    @kitchen = seed_kitchen!
    @order = seed_order!(token: "tok-shook-1")
    @order.update!(payment_state: "authorised", vipps_order_id: "cs_test_hook1",
                   payment_method: "stripe")
    ENV["STRIPE_WEBHOOK_SECRET"] = "whsec_test"
  end

  teardown do
    stripe_restore_http!
    ENV.delete("STRIPE_WEBHOOK_SECRET")
  end

  def signed_post(payload, header: nil)
    post stripe_callback_path,
         headers: { "Content-Type" => "application/json",
                    "Stripe-Signature" => header || stripe_signature_for(payload, secret: "whsec_test") },
         body: payload
  end

  test "answers 400 without a signature" do
    post stripe_callback_path, headers: { "Content-Type" => "application/json" },
                               body: { id: "evt_1" }.to_json

    assert_response :bad_request
    assert_equal "authorised", @order.reload.payment_state
  end

  test "answers 400 with a wrong signature" do
    signed_post({ id: "evt_1" }.to_json, header: "t=#{Time.current.to_i},v1=deadbeef")

    assert_response :bad_request
  end

  test "checkout.session.completed captures and confirms the order" do
    stripe_real_mode!
    event = {
      id: "evt_1", type: "checkout.session.completed",
      data: { object: { id: "cs_test_hook1", object: "checkout_session",
                        client_reference_id: "mrdamascy-tok-shook-1",
                        payment_status: "paid" } }
    }.to_json

    signed_post(event)

    assert_response :ok
    @order.reload
    assert_equal "captured", @order.payment_state
    assert_equal "confirmed", @order.state
  end

  test "replayed events are idempotent" do
    stripe_real_mode!
    event = {
      id: "evt_1", type: "checkout.session.completed",
      data: { object: { id: "cs_test_hook1", object: "checkout_session", client_reference_id: "mrdamascy-tok-shook-1" } }
    }.to_json

    2.times do
      signed_post(event)
      assert_response :ok
    end

    @order.reload
    assert_equal "captured", @order.payment_state
    assert_equal "confirmed", @order.state
  end

  test "unpaid session status leaves the order pending" do
    stripe_real_mode!(remote_status: "unpaid")
    event = {
      id: "evt_2", type: "checkout.session.completed",
      data: { object: { id: "cs_test_hook1", object: "checkout_session", client_reference_id: "mrdamascy-tok-shook-1" } }
    }.to_json

    signed_post(event)

    assert_response :ok
    assert_equal "authorised", @order.reload.payment_state,
                 "an unpaid session must not start cooking"
  end

  test "unknown sessions answer 200 without touching anything" do
    stripe_real_mode!
    event = {
      id: "evt_3", type: "checkout.session.completed",
      data: { object: { id: "cs_who_dis", object: "checkout_session", client_reference_id: "mrdamascy-who-dis" } }
    }.to_json

    signed_post(event)

    assert_response :ok
    assert_equal "authorised", @order.reload.payment_state
  end

  test "irrelevant event types answer 200 and change nothing" do
    stripe_real_mode!
    event = { id: "evt_4", type: "invoice.paid",
              data: { object: { id: "in_1", client_reference_id: "mrdamascy-tok-shook-1" } } }.to_json

    signed_post(event)

    assert_response :ok
    assert_equal "authorised", @order.reload.payment_state
  end

  test "malformed JSON answers 400" do
    signed_post("{not json")

    assert_response :bad_request
  end

  test "metadata tracking_token resolves too when client_reference_id is absent" do
    stripe_real_mode!
    event = {
      id: "evt_5", type: "checkout.session.completed",
      data: { object: { id: "cs_test_hook1", object: "checkout_session",
                        metadata: { tracking_token: "tok-shook-1" } } }
    }.to_json

    signed_post(event)

    assert_response :ok
    assert_equal "captured", @order.reload.payment_state
  end
end
