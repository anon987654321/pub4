# frozen_string_literal: true

require "test_helper"

class SharedAffiliateNetworkModelsTest < ActiveSupport::TestCase
  test "conversion postback aliases normalize and remain idempotent" do
    params = {
      "transactionId" => "amber-txn-1",
      "messageTypeId" => "5",
      "orderNumber" => "AMBER-ORD-9",
      "publisherCommission" => "12.50",
      "orderValue" => "250.00",
      "currencyId" => "NOK",
      "epi" => "city:bergen|surface:newsletter_weekly",
      "programId" => "42"
    }

    first = Shared::AffiliateConversion.record_from_postback!(params)
    second = Shared::AffiliateConversion.record_from_postback!(params)

    assert_equal first.id, second.id
    assert_equal "amber-txn-1", first.transaction_id
    assert_equal 42, first.program_id
    assert_equal "bergen", first.epi_parts["city"]
  end

  test "voucher API upsert retains fallback fields" do
    voucher = Shared::Tradedoubler::Voucher.new(
      external_id: "amber-voucher-#{SecureRandom.hex(4)}",
      program_id: "10",
      program_name: "Boozt",
      code: "SAVE10",
      title: "",
      short_description: "Site exclusive",
      description: "Long",
      voucher_type_id: 1,
      track_url: "",
      landing_url: "https://boozt.test/",
      discount_amount: 10,
      percentage: true,
      site_specific: true,
      exclusive: true,
      currency: "NOK",
      starts_at: 1.day.ago,
      ends_at: 7.days.from_now
    )

    record = Shared::AffiliateVoucher.upsert_from_api!(voucher)

    assert record.persisted?
    assert_equal "Offer", record.title
    assert_equal "https://boozt.test/", record.track_url
    assert_equal "voucher", record.type_name
  end
end
