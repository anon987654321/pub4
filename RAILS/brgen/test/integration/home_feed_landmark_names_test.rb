# frozen_string_literal: true

require "test_helper"

# The units between posts on the front page are complementary landmarks, and a
# landmark list where six of them are all "Sponsede produkter" tells a screen
# reader user nothing about which is which. axe's landmark-unique rule fails the
# page for it, and a seeded front page carries every kind of unit more than once.
class HomeFeedLandmarkNamesTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @author = User.strict_loading(false).create!(email_address: "landmarks@brgen.no", password: "password123",
                                                 city: @city)
    4.times do |i|
      Shared::AffiliateProduct.create!(
        source: "tradedoubler", external_id: "landmark-#{i}", title: "Vare #{i}",
        click_url: "https://example.test/l/#{i}", market: "NO", in_stock: true,
        placeholder: false, last_seen_at: Time.current
      )
    end
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "every unit between posts has its own accessible name" do
    ActsAsTenant.with_tenant(@city) do
      20.times { |n| Post.create!(user: @author, city: @city, title: "Innlegg #{n}", content: "Tekst #{n}") }
    end

    host! "brgen.no"
    get root_path

    assert_response :success
    labels = css_select("#home-feed aside").map { _1["aria-label"] }
    assert_operator labels.size, :>=, 6, "expected several units between posts"
    assert labels.all?(&:present?), "every unit names itself: #{labels.inspect}"
    assert_equal labels.uniq, labels, "two units share a name: #{labels.tally.select { _2 > 1 }.keys.inspect}"
    assert_includes labels, I18n.t("affiliate.feed_unit_label_after", position: 2, locale: :nb)
    assert_includes labels, I18n.t("home.radio_unit.label", position: 5, locale: :nb)
    assert_includes labels, I18n.t("promo.aria_label", position: 6, locale: :nb)
  end
end
