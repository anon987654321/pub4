# frozen_string_literal: true

require "test_helper"

class Marketplace::DealTest < ActiveSupport::TestCase
  test "ends_in is nil without an end" do
    assert_nil Marketplace::Deal.new(headline: "Tilbud").ends_in
  end

  test "ends_in is the remaining seconds while the deal is open" do
    remaining = Marketplace::Deal.new(headline: "Tilbud", ends_at: 2.hours.from_now).ends_in

    assert remaining
    assert_in_delta 2.hours, remaining, 2
  end

  test "ends_in is nil once the deal has ended" do
    assert_nil Marketplace::Deal.new(headline: "Tilbud", ends_at: 1.hour.ago).ends_in
  end

  # The deals index and its infinite-scroll reflex both search through this, and
  # a deal is found by its listing's title as well as its own words.
  test "matching finds a live deal by headline, badge or listing title" do
    Brgen::CitySeed.sync! if City.table_exists?
    city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.with_tenant(city) do
      seller = User.strict_loading(false).create!(email_address: "deal_match@brgen.no", password: "password123", city:)
      category = Marketplace::Category.create!(name: "Diverse-#{SecureRandom.hex(3)}")
      listing = Marketplace::Listing.create!(user: seller, title: "Racersykkel", category:,
                                             price_cents: 10_000, status: "active")
      deal = Marketplace::Deal.create!(listing:, headline: "Vårsalg", badge: "100% ekte")

      live = Marketplace::Deal.live.includes(:listing)
      assert_equal [ deal.id ], live.matching("racer").map(&:id)
      assert_equal [ deal.id ], live.matching("vårsalg").map(&:id)
      assert_equal [ deal.id ], live.matching("100%").map(&:id)
      assert_empty live.matching("0% ekte!").map(&:id), "% in the query is a literal, not a wildcard"
      assert_empty live.matching("sofa").map(&:id)
    end
  end

  test "countdown copy resolves in both shipped locales" do
    %i[nb en].each do |locale|
      assert I18n.exists?("marketplace.deals.ends_in", locale: locale), locale
      assert I18n.exists?("marketplace.deals.featured", locale: locale), locale
    end
  end
end
