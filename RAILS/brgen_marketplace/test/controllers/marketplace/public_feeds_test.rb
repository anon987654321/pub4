# frozen_string_literal: true

require "test_helper"

# The two public product feeds answered 500 for any listing with a photo. The
# engine is isolated, so url_for(attachment) found no Active Storage helper,
# and the merchant feed wrote namespaced elements through xml["g"], which in
# Builder is a String. The route contracts recorded both 500s (2026-11-04).
class Marketplace::PublicFeedsTest < ActionDispatch::IntegrationTest
  GOOGLE = { "g" => "http://base.google.com/ns/1.0" }.freeze

  setup do
    host! "markedsplass.brgen.no"
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    seller = User.create!(email_address: "feed-#{SecureRandom.hex(4)}@brgen.no", password: "secret1234")
    category = Marketplace::Category.create!(name: "Sport-#{SecureRandom.hex(3)}")
    @listing = Marketplace::Listing.create!(
      user: seller, title: "Ski #{SecureRandom.hex(3)}", category:,
      price_cents: 240_000, status: "active", currency: "NOK", kind: "goods"
    )
    photo = StringIO.new(ActiveSupport::TestCase::PIXEL_PNG)
    @listing.photos.attach(io: photo, filename: "ski.png", content_type: "image/png")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "the merchant feed lists a photographed listing with Google's namespaced fields" do
    get marketplace.merchant_feed_path

    assert_response :success
    item = Nokogiri::XML(response.body).at_xpath("//item[g:id='#{@listing.id}']", GOOGLE)
    assert item, "the listing is missing from the feed"
    assert_includes item.at_xpath("g:image_link", GOOGLE).text, "/rails/active_storage/"
  end

  test "the catalog lists a photographed listing with its image" do
    get marketplace.catalog_path

    assert_response :success
    row = JSON.parse(response.body)["items"].find { |item| item["title"] == @listing.title }
    assert row, "the listing is missing from the catalog"
    assert_includes row["image_url"].to_s, "/rails/active_storage/"
  end
end
