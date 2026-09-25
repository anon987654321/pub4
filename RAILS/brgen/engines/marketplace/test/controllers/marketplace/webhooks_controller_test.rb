# frozen_string_literal: true

require "test_helper"

# These webhooks are public, unauthenticated POSTs with skip_forgery_protection
# and no rate limit, and they can transition an order to paid. Before this suite
# existed, stripe checked only that a Stripe-Signature header was non-blank and
# vipps checked nothing, so anyone could mark any order paid.
class Marketplace::WebhooksControllerTest < ActionDispatch::IntegrationTest
  SECRET = "whsec_test_secret"

  setup do
    # The webhook routes live inside constraints(subdomain: MARKETPLACE_SUBDOMAINS),
    # so the default www.example.com host 404s before reaching the controller.
    host! "markedsplass.example.com"
    @seller = User.create!(email_address: "wh_seller@example.com", password: "secret1234")
    @buyer = User.create!(email_address: "wh_buyer@example.com",  password: "secret1234")
    @category = Marketplace::Category.create!(name: "Probe", slug: "probe-#{SecureRandom.hex(4)}")
    @listing = Marketplace::Listing.create!(title: "Webhook probe", price_cents: 1000,
                                            user: @seller, category: @category)
    @order = Marketplace::Order.create!(listing: @listing, buyer: @buyer,
                                        payment_reference: "ref_probe")
  end

  def stripe_payload
    { type: "checkout.session.completed",
      data: { object: { id: "ref_probe", payment_status: "paid", metadata: { order_id: @order.id } } } }.to_json
  end

  def signed_headers(payload, secret: SECRET, timestamp: Time.current.to_i)
    digest = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{payload}")
    { "Stripe-Signature" => "t=#{timestamp},v1=#{digest}", "CONTENT_TYPE" => "application/json" }
  end

  test "stripe rejects a forged event and leaves the order unpaid" do
    with_secret do
      post "/webhooks/stripe", params: stripe_payload,
           headers: { "Stripe-Signature" => "t=#{Time.current.to_i},v1=deadbeef", "CONTENT_TYPE" => "application/json" }

      assert_response :unauthorized
      assert_not_equal "paid", @order.reload.payment_status
    end
  end

  test "stripe rejects an event with no signature header at all" do
    with_secret do
      post "/webhooks/stripe", params: stripe_payload, headers: { "CONTENT_TYPE" => "application/json" }

      assert_response :unauthorized
      assert_not_equal "paid", @order.reload.payment_status
    end
  end

  test "stripe rejects a correctly signed but stale event (replay)" do
    with_secret do
      stale = 10.minutes.ago.to_i
      post "/webhooks/stripe", params: stripe_payload,
           headers: signed_headers(stripe_payload, timestamp: stale)

      assert_response :unauthorized
      assert_not_equal "paid", @order.reload.payment_status
    end
  end

  test "stripe fails closed when no webhook secret is configured" do
    post "/webhooks/stripe", params: stripe_payload, headers: signed_headers(stripe_payload)

    assert_response :unauthorized
    assert_not_equal "paid", @order.reload.payment_status
  end

  test "stripe accepts a correctly signed event and marks the order paid" do
    with_secret do
      post "/webhooks/stripe", params: stripe_payload, headers: signed_headers(stripe_payload)

      assert_response :ok
      assert_equal "paid", @order.reload.payment_status
      # One Stripe handler for both URLs: this host reaches the controller
      # brgen's own /webhooks/stripe does.
      assert_instance_of Webhooks::StripeController, controller
    end
  end

  test "vipps fails closed when unsigned" do
    post "/webhooks/vipps", params: { reference: "ref_probe", state: "AUTHORIZED" }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :unauthorized
    assert_not_equal "paid", @order.reload.payment_status
  end

  test "vipps pays the checkout, not a single colliding order line" do
    secret = "vipps_whsec"
    prior = ENV["VIPPS_WEBHOOK_SECRET"]
    ENV["VIPPS_WEBHOOK_SECRET"] = secret
    other = Marketplace::Listing.create!(title: "Line two", price_cents: 500, user: @seller, category: @category)
    second = Marketplace::Order.create!(listing: other, buyer: @buyer)
    address = Marketplace::Address.create!(
      user: @buyer, recipient: "Kari", line1: "Torget 1",
      postcode: "5003", city_name: "Bergen", country_code: "NO"
    )
    checkout = Marketplace::Checkout.create!(user: @buyer, marketplace_address: address, currency: "NOK")
    [ @order, second ].each { |row| row.update!(marketplace_checkout_id: checkout.id, payment_reference: "vipps_basket") }
    checkout.update!(status: "pending_payment", payment_reference: "vipps_basket")
    payload = { reference: "vipps_basket", state: "AUTHORIZED" }.to_json
    mac = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, payload))

    post "/webhooks/vipps", params: payload,
         headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "HMAC #{mac}" }

    assert_response :ok
    assert_equal "paid", checkout.reload.status
    assert_equal "paid", @order.reload.payment_status
    assert_equal "paid", second.reload.payment_status
  ensure
    ENV["VIPPS_WEBHOOK_SECRET"] = prior
  end


  test "dintero rejects an unsigned delivery before storing it" do
    body = {
      account_id: "P12345678",
      event: "checkout_transaction",
      event_delivery: SecureRandom.uuid,
      transaction: {
        id: "P12345678.txn1",
        merchant_reference: "ref_probe",
        status: "AUTHORIZED"
      }
    }.to_json

    post "/webhooks/dintero", params: body,
         headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :bad_request
    assert_equal 0, Marketplace::WebhookDelivery.count
  end

  test "dintero stores raw delivery identity and authorizes the order" do
    secret = "dintero_hook"
    prior = ENV["DINTERO_HOOK_SECRET"]
    prior_account = ENV["DINTERO_ACCOUNT_ID"]
    ENV["DINTERO_HOOK_SECRET"] = secret
    # The controller drops a delivery whose account_id is not ours, so the
    # accepting case must name the account it signs for.
    ENV["DINTERO_ACCOUNT_ID"] = "P12345678"
    delivery_id = SecureRandom.uuid
    body = {
      account_id: "P12345678",
      event: "checkout_transaction",
      event_delivery: delivery_id,
      transaction: {
        id: "P12345678.txn1",
        merchant_reference: "ref_probe",
        status: "AUTHORIZED"
      }
    }.to_json
    signature = OpenSSL::HMAC.hexdigest("SHA1", secret, body)

    post "/webhooks/dintero", params: body,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "event" => "checkout_transaction",
           "event-delivery" => delivery_id,
           "event-signature" => signature
         }

    assert_response :ok
    assert_equal "authorized", @order.reload.payment_status
    assert_equal 1, Marketplace::WebhookDelivery.where(event_delivery: delivery_id).count
    assert_equal "succeeded", Marketplace::WebhookDelivery.find_by!(event_delivery: delivery_id).status

    post "/webhooks/dintero", params: body,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "event" => "checkout_transaction",
           "event-delivery" => delivery_id,
           "event-signature" => signature
         }

    assert_response :ok
    assert_equal 1, Marketplace::WebhookDelivery.where(event_delivery: delivery_id).count
  ensure
    ENV["DINTERO_HOOK_SECRET"] = prior
    ENV["DINTERO_ACCOUNT_ID"] = prior_account
  end



  test "dintero rejects mismatched unsigned identity headers" do
    secret = "dintero_hook"
    prior = ENV["DINTERO_HOOK_SECRET"]
    ENV["DINTERO_HOOK_SECRET"] = secret
    delivery_id = SecureRandom.uuid
    body = {
      account_id: "P12345678",
      event: "checkout_transaction",
      event_delivery: delivery_id,
      transaction: {
        id: "txn-header",
        merchant_reference: "ref_probe",
        status: "AUTHORIZED"
      }
    }.to_json
    signature = OpenSSL::HMAC.hexdigest("SHA1", secret, body)

    post "/webhooks/dintero", params: body,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "event" => "checkout_authorization",
           "event-delivery" => SecureRandom.uuid,
           "event-signature" => signature
         }

    assert_response :bad_request
    assert_equal 0, Marketplace::WebhookDelivery.where(event_delivery: delivery_id).count
  ensure
    ENV["DINTERO_HOOK_SECRET"] = prior
  end

  private

  def with_secret
    prior = ENV["STRIPE_WEBHOOK_SECRET"]
    ENV["STRIPE_WEBHOOK_SECRET"] = SECRET
    yield
  ensure
    ENV["STRIPE_WEBHOOK_SECRET"] = prior
  end
end
