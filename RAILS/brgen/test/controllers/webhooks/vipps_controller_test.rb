# frozen_string_literal: true

require "test_helper"

# Vipps signs the method, path, date, host and a hash of the body. Each of those
# is a way in if it goes unchecked, so each gets a test that alters exactly one.
class Webhooks::VippsControllerTest < ActionDispatch::IntegrationTest
  SECRET_RAW = "vipps-test-secret"
  SECRET_B64 = Base64.strict_encode64(SECRET_RAW)

  def body(reference: "brgen-order-1-abc")
    { reference:, name: "EPAYMENTS", occurred: Time.now.httpdate }.to_json
  end

  def headers_for(payload, secret: SECRET_B64, date: Time.now.httpdate, host: "www.example.com", path: "/webhooks/vipps")
    content_hash = Base64.strict_encode64(Digest::SHA256.digest(payload))
    key = begin
      Base64.strict_decode64(secret)
    rescue ArgumentError
      secret
    end
    signature = Base64.strict_encode64(
      OpenSSL::HMAC.digest("SHA256", key, "POST\n#{path}\n#{date};#{host};#{content_hash}")
    )
    {
      "x-ms-date" => date,
      "x-ms-content-sha256" => content_hash,
      "Host" => host,
      "Authorization" => "HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=#{signature}",
      "CONTENT_TYPE" => "application/json"
    }
  end

  setup { ENV["VIPPS_WEBHOOK_SECRET"] = SECRET_B64 }
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
                              headers: headers_for(payload, secret: Base64.strict_encode64("wrong"))
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

  test "accepts a correctly signed callback" do
    payload = body
    post webhooks_vipps_path, params: payload, headers: headers_for(payload)
    assert_response :ok
  end

  # decode64 accepts anything, so a raw secret has to be detected rather than
  # decoded into plausible garbage.
  test "accepts a secret stored raw rather than base64" do
    ENV["VIPPS_WEBHOOK_SECRET"] = "not base64 at all!"
    payload = body
    post webhooks_vipps_path, params: payload, headers: headers_for(payload, secret: "not base64 at all!")
    assert_response :ok
  end
end
