# frozen_string_literal: true

require "test_helper"

# Vipps signs the method, path, date, host and a hash of the body. Each of those
# is a way in if it goes unchecked, so each gets a test that alters exactly one.
class Webhooks::VippsControllerTest < ActionDispatch::IntegrationTest
  SECRET = "vipps-test-secret"

  def body(reference: "brgen-order-1-abc")
    { reference:, name: "EPAYMENTS", occurred: Time.now.httpdate }.to_json
  end

  def headers_for(payload, secret: SECRET, date: Time.now.httpdate, host: "www.example.com", path: "/webhooks/vipps")
    content_hash = Base64.strict_encode64(Digest::SHA256.digest(payload))
    signature = Base64.strict_encode64(
      OpenSSL::HMAC.digest("SHA256", secret, "POST\n#{path}\n#{date};#{host};#{content_hash}")
    )
    {
      "x-ms-date" => date,
      "x-ms-content-sha256" => content_hash,
      "Host" => host,
      "Authorization" => "HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=#{signature}",
      "CONTENT_TYPE" => "application/json"
    }
  end

  setup { ENV["VIPPS_WEBHOOK_SECRET"] = SECRET }
  teardown { ENV.delete("VIPPS_WEBHOOK_SECRET") }

  test "rejects when the webhook secret is unset" do
    payload = body
    headers = headers_for(payload)
    ENV.delete("VIPPS_WEBHOOK_SECRET")
    post webhooks_vipps_path, params: payload, headers: headers
    assert_response :unauthorized
  end

  test "rejects missing auth headers" do
    post webhooks_vipps_path, params: body, headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :unauthorized
  end

  test "rejects a signature computed with the wrong secret" do
    payload = body
    post webhooks_vipps_path, params: payload,
                              headers: headers_for(payload, secret: "wrong")
    assert_response :unauthorized
  end

  test "rejects a body altered after signing" do
    headers = headers_for(body)
    post webhooks_vipps_path, params: body(reference: "brgen-order-999-xyz"), headers: headers
    assert_response :unauthorized
  end

  # The content hash is a header, so a caller could send a hash of the body they
  # wish they had sent. It has to be recomputed from the raw bytes, not trusted.
  test "rejects a content hash that does not match the body" do
    payload = body
    headers = headers_for(payload)
    headers["x-ms-content-sha256"] = Base64.strict_encode64(Digest::SHA256.digest("something else"))
    post webhooks_vipps_path, params: payload, headers: headers
    assert_response :unauthorized
  end

  # A valid signature that never expires is a replay waiting to happen.
  test "rejects a signature outside the timestamp tolerance" do
    payload = body
    stale = (Time.now - Webhooks::VippsController::TOLERANCE_SECONDS - 60).httpdate
    post webhooks_vipps_path, params: payload, headers: headers_for(payload, date: stale)
    assert_response :unauthorized
  end

  # An aborted or expired payment was ignored, so the order stayed
  # pending_payment and the buyer could never pay again.
  test "an aborted payment returns the order to payable" do
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    buyer = User.create!(email_address: "va-#{SecureRandom.hex(4)}@brgen.no", password: "password123")
    listing = Marketplace::Listing.create!(
      user: User.create!(email_address: "vs-#{SecureRandom.hex(4)}@brgen.no", password: "password123"),
      title: "Ting #{SecureRandom.hex(3)}", category: Marketplace::Category.create!(name: "D-#{SecureRandom.hex(3)}"),
      price_cents: 20_000, status: "active", currency: "NOK"
    )
    order = Marketplace::Order.create!(buyer:, listing:, quantity: 1, price_cents: 20_000)
    reference = "brgen-order-#{order.id}-abcd1234"
    order.mark_payment_pending!(provider: "vipps", reference:)

    payload = { reference:, name: "ABORTED", success: true, occurred: Time.current.httpdate }.to_json
    post webhooks_vipps_path, params: payload, headers: headers_for(payload)

    assert_response :ok
    assert_equal "failed", order.reload.payment_status
    assert order.startable?, "the buyer cannot try the payment again"
  ensure
    ActsAsTenant.current_tenant = nil
  end

  # A basket is one Vipps payment over several sellers' lines. AUTHORIZED has
  # to pay every line once; the CAPTURED that follows, or a redelivery, must
  # not pay any of them again.
  test "an authorized basket payment pays every line in it exactly once" do
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    buyer = User.create!(email_address: "vb-#{SecureRandom.hex(4)}@brgen.no", password: "password123")
    category = Marketplace::Category.create!(name: "B-#{SecureRandom.hex(3)}")
    basket = Marketplace::Checkout.create!(user: buyer, status: "open")

    lines = 2.times.map do |n|
      seller = User.create!(email_address: "vbs#{n}-#{SecureRandom.hex(4)}@brgen.no", password: "password123")
      listing = category.listings.create!(user: seller, title: "Ting #{n} #{SecureRandom.hex(3)}",
                                          price_cents: 10_000, status: "active", currency: "NOK")
      basket.orders.create!(buyer:, listing:, quantity: 1, price_cents: 10_000)
    end
    reference = Marketplace::Payments::VippsCheckout.reference_for(basket)
    basket.mark_payment_pending!(provider: "vipps", reference:)

    authorized = { reference:, name: "AUTHORIZED", success: true, occurred: Time.current.httpdate }.to_json
    post webhooks_vipps_path, params: authorized, headers: headers_for(authorized)

    assert_response :ok
    assert_equal "paid", basket.reload.status
    lines.each(&:reload)
    assert_equal %w[paid paid], lines.map(&:payment_status)
    paid_at = lines.map(&:paid_at)
    assert paid_at.all?, "a line has no paid_at"

    captured = { reference:, name: "CAPTURED", success: true, occurred: Time.current.httpdate }.to_json
    assert_no_difference -> { Notification.count } do
      post webhooks_vipps_path, params: captured, headers: headers_for(captured)
      post webhooks_vipps_path, params: authorized, headers: headers_for(authorized)
    end
    lines.each(&:reload)
    assert_equal paid_at, lines.map(&:paid_at)
  ensure
    ActsAsTenant.current_tenant = nil
  end

  test "accepts a correctly signed callback" do
    payload = body
    post webhooks_vipps_path, params: payload, headers: headers_for(payload)
    assert_response :ok
  end
end
