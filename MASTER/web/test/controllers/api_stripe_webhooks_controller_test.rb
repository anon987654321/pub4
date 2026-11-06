# frozen_string_literal: true

require "test_helper"
require "openssl"

# Stripe's subscription events keep each law API key's status in step.
class ApiStripeWebhooksControllerTest < ActionDispatch::IntegrationTest
  SECRET = "whsec_webhook_test"

  setup do
    @saved_secret = ENV["STRIPE_WEBHOOK_SECRET"]
    ENV["STRIPE_WEBHOOK_SECRET"] = SECRET
  end

  teardown { ENV["STRIPE_WEBHOOK_SECRET"] = @saved_secret }

  def deliver(event, secret: SECRET, signed_at: Time.now.to_i)
    payload = event.to_json
    signature = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{signed_at}.#{payload}")
    headers = { "Stripe-Signature" => "t=#{signed_at},v1=#{signature}", "Content-Type" => "application/json" }
    post api_webhooks_stripe_path, params: payload, headers:
  end

  def subscription_event(type, status)
    { "type" => type, "data" => { "object" => { "id" => "sub_hook_1", "status" => status, "customer" => "cus_hook",
                                                  "metadata" => { "plan" => "master_api_team" } } } }
  end

  test "a signed subscription event creates and then updates the key" do
    deliver(subscription_event("customer.subscription.created", "active"))
    assert_response :ok
    assert_equal "active", ApiKey.find_by!(stripe_subscription_id: "sub_hook_1").status

    deliver(subscription_event("customer.subscription.deleted", "canceled"))
    assert_response :ok
    assert_equal "canceled", ApiKey.find_by!(stripe_subscription_id: "sub_hook_1").status
  end

  test "a bad signature is refused and changes nothing" do
    deliver(subscription_event("customer.subscription.created", "active"), secret: "whsec_forged")

    assert_response :unauthorized
    assert_nil ApiKey.find_by(stripe_subscription_id: "sub_hook_1")
  end

  test "a stale signature is refused" do
    deliver(subscription_event("customer.subscription.created", "active"), signed_at: Time.now.to_i - 3600)

    assert_response :unauthorized
  end

  test "an event that is not a subscription event is acknowledged and ignored" do
    deliver({ "type" => "invoice.paid", "data" => { "object" => { "id" => "in_1" } } })

    assert_response :ok
    assert_equal 0, ApiKey.count
  end

  test "a subscription to another app's plan makes no key" do
    event = subscription_event("customer.subscription.created", "active")
    event["data"]["object"]["metadata"]["plan"] = "amber_premium_monthly"
    deliver(event)

    assert_response :ok
    assert_nil ApiKey.find_by(stripe_subscription_id: "sub_hook_1")
  end
end
