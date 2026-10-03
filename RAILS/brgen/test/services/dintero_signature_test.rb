# frozen_string_literal: true

require "test_helper"

class DinteroSignatureTest < ActiveSupport::TestCase
  setup do
    @saved = {
      "DINTERO_ACCOUNT_ID" => ENV["DINTERO_ACCOUNT_ID"],
      "DINTERO_CALLBACK_SECRET" => ENV["DINTERO_CALLBACK_SECRET"],
      "DINTERO_HOOK_SECRET" => ENV["DINTERO_HOOK_SECRET"]
    }
    ENV["DINTERO_ACCOUNT_ID"] = "P12345678"
    ENV["DINTERO_CALLBACK_SECRET"] = "callback-secret"
    ENV["DINTERO_HOOK_SECRET"] = "hook-secret"
  end

  teardown do
    @saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "callback signature round trips" do
    request = Struct.new(:request_method, :url).new(
      "GET",
      "https://markedsplass.brgen.no/webhooks/dintero/callback?session_id=abc&foo=2&foo=1"
    )
    timestamp = Time.current.to_i
    header = Marketplace::Payments::DinteroSignature.callback_header(
      timestamp: timestamp,
      method: request.request_method,
      url: request.url
    )
    assert Marketplace::Payments::DinteroSignature.valid_callback?(
      header: header,
      request: request
    )
  end

  test "callback rejects stale signatures and wrong secrets" do
    request = Struct.new(:request_method, :url).new(
      "GET",
      "https://markedsplass.brgen.no/webhooks/dintero/callback?session_id=abc"
    )
    stale = 10.minutes.ago.to_i
    header = Marketplace::Payments::DinteroSignature.callback_header(
      timestamp: stale,
      method: request.request_method,
      url: request.url
    )
    assert_not Marketplace::Payments::DinteroSignature.valid_callback?(header:, request:)

    ENV["DINTERO_CALLBACK_SECRET"] = "wrong"
    assert_not Marketplace::Payments::DinteroSignature.valid_callback?(header:, request:)
  end


  test "callback canonicalization sorts duplicate query keys by value" do
    request = Struct.new(:request_method, :url).new(
      "GET",
      "https://markedsplass.brgen.no/webhooks/dintero/callback?foo=2&foo=1"
    )
    canonical = Struct.new(:request_method, :url).new(
      "GET",
      "https://markedsplass.brgen.no/webhooks/dintero/callback?foo=1&foo=2"
    )
    header = Marketplace::Payments::DinteroSignature.callback_header(
      timestamp: Time.current.to_i,
      method: canonical.request_method,
      url: canonical.url
    )

    assert Marketplace::Payments::DinteroSignature.valid_callback?(
      header:,
      request: request
    )
  end


  test "missing webhook secret rejects even with a validly shaped digest" do
    ENV.delete("DINTERO_HOOK_SECRET")
    body = '{"event":"checkout_transaction"}'
    header = OpenSSL::HMAC.hexdigest("SHA1", "", body)

    assert_not Marketplace::Payments::DinteroSignature.valid_webhook?(header:, body:)
  end

  test "missing callback secret rejects without raising" do
    ENV.delete("DINTERO_CALLBACK_SECRET")
    request = Struct.new(:request_method, :url).new(
      "GET",
      "https://markedsplass.brgen.no/webhooks/dintero/callback?session_id=abc"
    )

    assert_not Marketplace::Payments::DinteroSignature.valid_callback?(
      header: "t=#{Time.current.to_i},v0-hmac-sha256=deadbeef",
      request:
    )
  end

  test "webhook signature covers raw bytes" do
    body = '{"event":"checkout_transaction","x":1}'
    signature = OpenSSL::HMAC.hexdigest("SHA1", "hook-secret", body)
    assert Marketplace::Payments::DinteroSignature.valid_webhook?(header: signature, body:)
    assert_not Marketplace::Payments::DinteroSignature.valid_webhook?(
      header: signature,
      body: '{"x":1,"event":"checkout_transaction"}'
    )
  end
end
