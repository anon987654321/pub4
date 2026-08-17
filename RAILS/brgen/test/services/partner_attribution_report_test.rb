# frozen_string_literal: true

require "test_helper"

# The report exists to tell two zeros apart: nobody clicked, and tracking is
# broken. A network dashboard reports both as zero conversions, and before
# outbound clicks were counted nothing in the tree could distinguish them.
class PartnerAttributionReportTest < ActiveSupport::TestCase
  setup do
    Shared::OutboundClick.delete_all
    Shared::AffiliateConversion.delete_all if defined?(Shared::AffiliateConversion)
  end

  def click(merchant:, epi: nil, at: Time.current)
    Shared::OutboundClick.create!(app: "brgen", merchant: merchant, url_host: "shop.example",
                                  epi: epi, guest: true, created_at: at)
  end

  test "no clicks says the beacon may not be firing rather than reporting a bare zero" do
    output = PartnerAttributionReport.new.render

    assert_match(/clicks\s+0/, output)
    assert_match(/beacon is not firing/, output)
  end

  test "clicks with no conversions is the useful zero and says so" do
    click(merchant: "Zalando")
    click(merchant: "Zalando")
    click(merchant: "Ellos")

    output = PartnerAttributionReport.new.render

    assert_match(/clicks\s+3/, output)
    assert_match(/Zalando\s+2/, output)
    assert_match(/attribution before looking at the offer/, output)
  end

  test "clicks outside the window are not counted" do
    click(merchant: "Zalando", at: 30.days.ago)

    assert_equal 0, PartnerAttributionReport.new(window: 7.days).clicks_total
    assert_equal 1, PartnerAttributionReport.new(window: 60.days).clicks_total
  end

  # The number to drive to zero: a click with no epi cannot be matched to the
  # conversion it causes, so that conversion lands in unattributed.
  test "clicks without an epi are counted separately" do
    click(merchant: "Zalando", epi: "city:bergen|surface:marketplace")
    click(merchant: "Ellos", epi: nil)

    report = PartnerAttributionReport.new

    assert_equal 2, report.clicks_total
    assert_equal 1, report.clicks_without_epi
  end

  test "a conversion whose epi matches no recorded click is unattributed" do
    skip "Shared::AffiliateConversion not loaded" unless defined?(Shared::AffiliateConversion)

    click(merchant: "Zalando", epi: "city:bergen|surface:marketplace")
    Shared::AffiliateConversion.create!(source: "tradedoubler", message_type_id: 1,
                                epi: "city:bergen|surface:marketplace")
    Shared::AffiliateConversion.create!(source: "tradedoubler", message_type_id: 1, epi: "epi:we:never:sent")

    assert_equal 1, PartnerAttributionReport.new.unattributed_conversions
  end

  # A host, never a full URL: the question is which merchants get traffic, not
  # what each visitor shops for.
  test "the click record keeps a host and not a path" do
    Shared::OutboundClick.record(app: "brgen", url: "https://www.shop.example/very/private/path?q=1",
                                 merchant: "Shop")

    stored = Shared::OutboundClick.last

    assert_equal "shop.example", stored.url_host
    refute_includes stored.attributes.values.map(&:to_s).join, "private"
  end

  test "a non-http url records nothing rather than a row we cannot attribute" do
    assert_nil Shared::OutboundClick.record(app: "brgen", url: "javascript:alert(1)")
    assert_nil Shared::OutboundClick.record(app: "brgen", url: "/relative/path")
    assert_equal 0, Shared::OutboundClick.count
  end
end
