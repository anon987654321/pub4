# frozen_string_literal: true

require "test_helper"

# Duplicate-listing detection: the same seller posting the same normalised
# title while the first is still active files exactly one open moderation
# report on the new listing — and nothing else counts. A sold sibling is a
# relisting, a different title is a different thing, and detection never
# withdraws anything itself.
class MarketplaceDuplicateDetectionTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @seller = User.strict_loading(false).create!(email_address: "dup-seller@brgen.no", password: "password123", city: @city)
    @category = Marketplace::Category.find_or_create_by!(name: "DupCheck", slug: "dupcheck-#{SecureRandom.hex(4)}")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def listing!(title)
    ActsAsTenant.with_tenant(@city) do
      Marketplace::Listing.create!(user: @seller, category: @category, title: title, price_cents: 5_000, currency: "NOK")
    end
  end

  def open_reports(listing)
    ModerationReport.where(reportable: listing, reason: "duplicate", status: "open")
  end

  test "normalisation folds case, punctuation and runs of whitespace" do
    assert_equal "sofa 3 seat", Marketplace::Listing.normalize_title("  Sofa!  3-seat?? ")
    assert_equal "sofa 3 seat", Marketplace::Listing.normalize_title("SOFA   3 SEAT")
  end

  test "a second active listing with the same normalised title is reported once" do
    first = listing!("Vintage bed frame")
    second = listing!("vintage  bed-frame!")

    assert_empty open_reports(first), "the first listing is the original, not the copy"
    assert_equal 1, open_reports(second).count
    assert_equal @seller.id, open_reports(second).first.user_id
  end

  test "editing nothing and re-reporting never multiplies the report" do
    listing!("Vintage bed frame")
    second = listing!("vintage bed frame")

    second.send(:file_duplicate_report)

    assert_equal 1, open_reports(second).count
  end

  test "a sold sibling is a relisting, not a duplicate" do
    first = listing!("Vintage bed frame")
    first.mark_sold!

    assert_empty open_reports(listing!("Vintage bed frame"))
  end

  test "a different title is a different thing" do
    listing!("Vintage bed frame")

    assert_empty open_reports(listing!("Vintage bed slats"))
  end

  test "a duplicate listing finds its twin; an original finds nothing" do
    first = listing!("Vintage bed frame")
    second = listing!("vintage  bed-frame!")

    assert_nil first.duplicate_of
    assert_equal first.id, second.duplicate_of.id
  end
end
