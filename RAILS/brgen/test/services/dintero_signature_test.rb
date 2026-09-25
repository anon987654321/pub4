# frozen_string_literal: true

require "test_helper"

class DinteroSignatureTest < ActiveSupport::TestCase
  setup do
    @saved = {
      "DINTERO_ACCOUNT_ID" => ENV["DINTERO_ACCOUNT_ID"],
      "DINTERO_CALLBACK_SECRET" => ENV["DINTERO_CALLBACK_SECRET"],
      "DINTERO_HOOK_SECRET" => ENV["DINTERO_HOOK_SECRET"]
    }
    ENV["DINTERO_ACCOUNT_ID"] = "T12345678"
    ENV["DINTERO_CALLBACK_SECRET"] = "callback-secret"
    ENV["DINTERO_HOOK_SECRET"] = "hook-secret"
  end

  teardown do
    @saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "callback signature round trips against the exact URL" do
    url = "https://markedsplass.brgen.no/webhooks/dintero/callback?session_id=s1&transaction_id=t1"
    request = ActionDispatch::Request.new(Rack::MockRequest.env_for(url, method: "GET"))
    header = Marketplace::Payments::DinteroSignature.callback_header(
      timestamp: Time.current.to_i,
      method: "GET",
      url: url
    )

    assert Marketplace::Payments::DinteroSignature.valid_callback?(header:, request:)
  end

  test "callback signatures older than five minutes fail" do
    url = "https://markedsplass.brgen.no/webhooks/dintero/callback?transaction_id=t1"
    request = ActionDispatch::Request.new(Rack::MockRequest.env_for(url, method: "GET"))
    timestamp = 301.seconds.ago.to_i
    header = Marketplace::Payments::DinteroSignature.callback_header(
      timestamp:,
      method: "GET",
      url:
    )

    assert_not Marketplace::Payments::DinteroSignature.valid_callback?(header:, request:)
  end

  test "webhook signature covers raw body bytes" do
    body = '{"event":"checkout_transaction","amount":10000}'
    signature = OpenSSL::HMAC.hexdigest("SHA1", ENV.fetch("DINTERO_HOOK_SECRET"), body)

    assert Marketplace::Payments::DinteroSignature.valid_webhook?(header: signature, body:)
    refute Marketplace::Payments::DinteroSignature.valid_webhook?(
      header: signature,
      body: JSON.pretty_generate(JSON.parse(body))
    )
  end

  test "wrong webhook secret fails closed" do
    body = '{"event":"checkout_transaction"}'
    signature = OpenSSL::HMAC.hexdigest("SHA1", "wrong-secret", body)

    assert_not Marketplace::Payments::DinteroSignature.valid_webhook?(header: signature, body:)
  end
end
