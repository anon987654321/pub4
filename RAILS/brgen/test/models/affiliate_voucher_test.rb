# frozen_string_literal: true

require "test_helper"

class AffiliateVoucherTest < ActiveSupport::TestCase
  test "upserts from API struct" do
    skip "migration not applied" unless Shared::AffiliateVoucher.table_exists?

    voucher = Shared::Tradedoubler::Voucher.new(
      external_id: "v1",
      program_id: "10",
      program_name: "Boozt",
      code: "SAVE10",
      title: "10% off",
      short_description: "Site exclusive",
      description: "Long",
      voucher_type_id: 1,
      track_url: "https://clk.test/v",
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
    assert_equal "SAVE10", record.code
    assert_includes Shared::AffiliateVoucher.live, record
    assert_equal "voucher", record.type_name
  end
end
