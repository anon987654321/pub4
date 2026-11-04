# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# start! fetched a fresh Vipps access token on every checkout, though a token
# lives about a day, and a refused token call surfaced as a KeyError on the
# missing access_token rather than as the provider's answer.
class VippsAccessTokenTest < ActiveSupport::TestCase
  KEYS = %w[VIPPS_EPAYMENT_CLIENT_ID VIPPS_EPAYMENT_CLIENT_SECRET VIPPS_MSN
            VIPPS_SUBSCRIPTION_KEY VIPPS_API_BASE VIPPS_TEST_MODE].freeze

  setup do
    @saved = KEYS.to_h { |k| [ k, ENV[k] ] }
    KEYS.each { |k| ENV.delete(k) }
    { "VIPPS_EPAYMENT_CLIENT_ID" => "id", "VIPPS_EPAYMENT_CLIENT_SECRET" => "secret",
      "VIPPS_MSN" => "123456", "VIPPS_SUBSCRIPTION_KEY" => "sub" }.each { |k, v| ENV[k] = v }
  end

  teardown { @saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v } }

  def answer(klass, code:, body:)
    response = klass.new("1.1", code, "")
    response.define_singleton_method(:body) { body }
    response
  end

  def token_calls(response, times)
    calls = 0
    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      Net::HTTP.stub(:start, ->(*, **) { calls += 1; response }) do
        times.times { Marketplace::Payments::VippsCheckout.send(:access_token) }
      end
    end
    calls
  end

  test "one token is fetched for its lifetime, not once per checkout" do
    ok = answer(Net::HTTPOK, code: "200", body: { access_token: "tok", expires_in: "86398" }.to_json)

    assert_equal 1, token_calls(ok, 3)
  end

  test "a refused token call raises ProviderError with the status" do
    refused = answer(Net::HTTPUnauthorized, code: "401", body: "<html>Unauthorized</html>")

    error = assert_raises(Marketplace::Payments::ProviderError) { token_calls(refused, 1) }
    assert_includes error.message, "401"
  end
end
