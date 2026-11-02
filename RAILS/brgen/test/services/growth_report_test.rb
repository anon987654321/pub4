# frozen_string_literal: true

require "test_helper"

class GrowthReportTest < ActiveSupport::TestCase
  setup do
    Shared::VisitCount.delete_all
    Shared::OutboundClick.delete_all
    Shared::AffiliateConversion.delete_all
  end

  test "renders the existing measurable growth signals without inventing revenue" do
    Shared::VisitCount.record(app: "brgen", host: "brgen.no", route: "home#index", day: Date.current)
    Shared::VisitCount.record(app: "brgen", host: "oshlo.no", route: "home#index", day: Date.current)
    Shared::OutboundClick.create!(
      app: "brgen", url_host: "shop.example", surface: "marketplace",
      merchant: "Shop", guest: true, created_at: Time.current
    )

    report = Shared::GrowthReport.new

    assert_equal 2, report.visits
    assert_equal 1, report.outbound_clicks
    assert_equal({ "brgen.no" => 1, "oshlo.no" => 1 }, report.visits_by_host)
    assert_match(/paid marketplace orders\s+0/, report.render)
    assert_match(/outbound merchant clicks\s+1/, report.render)
    assert_match(/external order value\s+0\.00/, report.render)
  end

  test "reports approved affiliate commission separately from gross order value" do
    Shared::AffiliateConversion.create!(
      source: "tradedoubler", transaction_id: "growth-approved", message_type_id: 5,
      order_value: BigDecimal("100.00"), publisher_commission: BigDecimal("7.50"),
      currency: "NOK", epi: "city:bergen|surface:marketplace"
    )
    Shared::AffiliateConversion.create!(
      source: "tradedoubler", transaction_id: "growth-pending", message_type_id: 4,
      order_value: BigDecimal("200.00"), publisher_commission: BigDecimal("99.00"),
      currency: "NOK", epi: "city:bergen|surface:marketplace"
    )

    report = Shared::GrowthReport.new

    assert_equal 1, report.affiliate_conversions
    assert_equal 100.0, report.affiliate_order_value
    assert_equal({ "NOK" => BigDecimal("7.50") }, report.approved_affiliate_commission_by_currency)
    assert_includes report.render, "7.50"
    assert_includes report.render, "gross, not publisher revenue"
  end

  test "excludes signals outside the report window" do
    old_day = 31.days.ago.to_date
    Shared::VisitCount.record(app: "brgen", host: "brgen.no", route: "home#index", day: old_day)

    assert_equal 0, Shared::GrowthReport.new(window: 30.days).visits
  end
end
