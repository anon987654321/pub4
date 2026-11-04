# frozen_string_literal: true

require "test_helper"

# Copy the marketplace writes from Ruby rather than a view: the shipping
# notification and the "why you see this" ranking badges. Both had English
# literals or English-only defaults, so a Norwegian reader met English.
class Marketplace::OrderAndRankingCopyTest < ActiveSupport::TestCase
  REASONS = %w[title_match title_partial description_match category_match
               preferred_category fast_delivery trusted_seller quality_signal].freeze

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @buyer = User.strict_loading(false).create!(email_address: "copy_buyer_#{SecureRandom.hex(3)}@brgen.no",
                                                password: "password123", city: @city)
    seller = User.strict_loading(false).create!(email_address: "copy_seller_#{SecureRandom.hex(3)}@brgen.no",
                                                password: "password123", city: @city)
    category = Marketplace::Category.create!(name: "Kopi-#{SecureRandom.hex(3)}")
    item = Marketplace::Listing.create!(user: seller, title: "Sykkel", category:, price_cents: 50_000,
                                        status: "active", currency: "NOK")
    @order = Marketplace::Order.create!(buyer: @buyer, listing: item, quantity: 1, price_cents: 50_000)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "a shipped order without a carrier tells a Norwegian buyer about sporing" do
    I18n.with_locale(:nb) { @order.ship!(tracking_code: "NO123") }

    body = @buyer.notifications.order(:id).last.then { _1.try(:body) || _1.params.to_s }
    assert_includes body, "#{I18n.t('marketplace.order_notification.tracking', locale: :nb)}: NO123"
    refute_includes body, "Tracking:"
  end

  test "every ranking reason is translated in both languages" do
    %i[nb en].each do |locale|
      REASONS.each do |reason|
        assert I18n.exists?("marketplace.ranking_reasons.#{reason}", locale),
               "marketplace.ranking_reasons.#{reason} is missing in #{locale}"
      end
    end
    refute_equal I18n.t("marketplace.ranking_reasons.title_match", locale: :en),
                 I18n.t("marketplace.ranking_reasons.title_match", locale: :nb)
  end

  test "a listing is badged in Norwegian by how it meets the search" do
    listing = @order.listing
    ranker = ->(query) { Marketplace::SearchRanker.new(Marketplace::Listing.all, query:, viewer: nil) }

    I18n.with_locale(:nb) do
      assert_includes ranker.call("sykkel").reasons(listing), I18n.t("marketplace.ranking_reasons.title_match")
      assert_includes ranker.call("sykkel ski").reasons(listing), I18n.t("marketplace.ranking_reasons.title_partial")
      refute_includes ranker.call("").reasons(listing), I18n.t("marketplace.ranking_reasons.title_match")
    end
  end
end
