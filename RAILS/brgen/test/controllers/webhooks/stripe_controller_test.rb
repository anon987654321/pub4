# frozen_string_literal: true

require "test_helper"

# A signature check has two ways to be wrong and only one of them is loud.
# Failing closed means orders never reach paid and someone eventually notices;
# failing open means anyone who can reach the URL can mark an order paid, and
# nothing notices at all. Both directions are pinned here.
class Webhooks::StripeControllerTest < ActionDispatch::IntegrationTest
  SECRET = "whsec_test_secret"

  def sign(payload, secret: SECRET, timestamp: Time.now.to_i)
    digest = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{payload}")
    "t=#{timestamp},v1=#{digest}"
  end

  def event(payment_status: "paid", reference: nil)
    {
      type: "checkout.session.completed",
      data: { object: { payment_status:, client_reference_id: reference } },
    }.to_json
  end

  def post_event(payload, header)
    post webhooks_stripe_path, params: payload,
                               headers: { "Stripe-Signature" => header, "CONTENT_TYPE" => "application/json" }
  end

  setup { ENV["STRIPE_WEBHOOK_SECRET"] = SECRET }
  teardown { ENV.delete("STRIPE_WEBHOOK_SECRET") }

  test "rejects when the signing secret is unset" do
    ENV.delete("STRIPE_WEBHOOK_SECRET")
    payload = event
    post_event(payload, sign(payload))
    assert_response :unauthorized
  end

  test "rejects a missing signature header" do
    post_event(event, "")
    assert_response :unauthorized
  end

  test "rejects a signature computed with the wrong secret" do
    payload = event
    post_event(payload, sign(payload, secret: "whsec_wrong"))
    assert_response :unauthorized
  end

  # The signature covers the raw bytes. A body altered after signing must not
  # verify, or the signature is decorative.
  test "rejects a body altered after signing" do
    header = sign(event)
    post_event(event(reference: "order_id:999"), header)
    assert_response :unauthorized
  end

  test "rejects a signature outside the timestamp tolerance" do
    payload = event
    stale = Time.now.to_i - Webhooks::StripeController::TOLERANCE_SECONDS - 60
    post_event(payload, sign(payload, timestamp: stale))
    assert_response :unauthorized
  end

  test "accepts a correctly signed event" do
    payload = event
    post_event(payload, sign(payload))
    assert_response :ok
  end

  # Stripe sends every valid v1 during a signing-secret rotation, and the old
  # one comes first. Accepting only the first would break every rotation.
  test "accepts when a valid signature follows an invalid one" do
    payload = event
    timestamp = Time.now.to_i
    good = OpenSSL::HMAC.hexdigest("SHA256", SECRET, "#{timestamp}.#{payload}")
    post_event(payload, "t=#{timestamp},v1=#{'0' * good.length},v1=#{good}")
    assert_response :ok
  end

  test "reports malformed json as a bad request rather than a server error" do
    payload = "{not json"
    post_event(payload, sign(payload))
    assert_response :bad_request
  end
end
