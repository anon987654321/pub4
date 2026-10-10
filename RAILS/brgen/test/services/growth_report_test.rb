# frozen_string_literal: true

require "test_helper"

class GrowthReportTest < ActiveSupport::TestCase
  setup do
    Shared::VisitCount.delete_all
    Shared::OutboundClick.delete_all
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

  test "excludes signals outside the report window" do
    old_day = 31.days.ago.to_date
    Shared::VisitCount.record(app: "brgen", host: "brgen.no", route: "home#index", day: old_day)

    assert_equal 0, Shared::GrowthReport.new(window: 30.days).visits
  end
end
