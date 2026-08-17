# frozen_string_literal: true

require "test_helper"

class AffiliateConversionTest < ActiveSupport::TestCase
  test "records a postback and is idempotent on transaction+message" do
    skip "migration not applied" unless Shared::AffiliateConversion.table_exists?

    params = {
      "transactionId" => "txn-1",
      "messageTypeId" => "5",
      "orderNumber" => "ORD-9",
      "publisherCommission" => "12.50",
      "orderValue" => "250.00",
      "currencyId" => "NOK",
      "epi" => "city:bergen|surface:newsletter_weekly",
      "programId" => "42"
    }

    first = Shared::AffiliateConversion.record_from_postback!(params)
    second = Shared::AffiliateConversion.record_from_postback!(params)

    assert_equal first.id, second.id
    assert_equal 1, Shared::AffiliateConversion.where(transaction_id: "txn-1").count
    assert first.approved?
    assert_equal "bergen", first.epi_parts["city"]
    assert_equal "newsletter_weekly", first.epi_parts["surface"]
  end

  test "rejects blank message type" do
    skip "migration not applied" unless Shared::AffiliateConversion.table_exists?

    assert_nil Shared::AffiliateConversion.record_from_postback!({ "orderNumber" => "x" })
  end
end
