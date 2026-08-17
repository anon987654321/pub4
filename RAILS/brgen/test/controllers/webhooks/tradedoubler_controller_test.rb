# frozen_string_literal: true

require "test_helper"

class Webhooks::TradedoublerControllerTest < ActionDispatch::IntegrationTest
  setup do
    skip "migration not applied" unless Shared::AffiliateConversion.table_exists?
  end

  test "rejects when webhook secret unset" do
    ENV.delete("TRADEDOUBLER_WEBHOOK_SECRET")
    ENV.delete("TRADEDOUBLER_CONVERSIONS_TOKEN")
    post webhooks_tradedoubler_path, params: { messageTypeId: 5, transactionId: "t1" }
    assert_response :unauthorized
  end

  test "rejects wrong token" do
    ENV["TRADEDOUBLER_WEBHOOK_SECRET"] = "secret-ok"
    post webhooks_tradedoubler_path, params: { messageTypeId: 5, transactionId: "t1", token: "nope" }
    assert_response :unauthorized
  ensure
    ENV.delete("TRADEDOUBLER_WEBHOOK_SECRET")
  end

  test "accepts signed postback" do
    ENV["TRADEDOUBLER_WEBHOOK_SECRET"] = "secret-ok"
    post webhooks_tradedoubler_path, params: {
      token: "secret-ok",
      messageTypeId: 5,
      transactionId: "t-accept",
      orderNumber: "O1",
      publisherCommission: "1.00",
      epi: "city:bergen"
    }
    assert_response :ok
    assert Shared::AffiliateConversion.exists?(transaction_id: "t-accept", message_type_id: 5)
  ensure
    ENV.delete("TRADEDOUBLER_WEBHOOK_SECRET")
  end
end
