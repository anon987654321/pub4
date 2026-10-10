# frozen_string_literal: true

require "test_helper"

class Marketplace::BuyBoxSelectorTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @category = Marketplace::Category.create!(name: "Buy Box #{SecureRandom.hex(3)}")
    @seller_a = User.strict_loading(false).create!(email_address: "buybox-a-#{SecureRandom.hex(3)}@brgen.no", password: "password123", city: @city)
    @seller_b = User.strict_loading(false).create!(email_address: "buybox-b-#{SecureRandom.hex(3)}@brgen.no", password: "password123", city: @city)
    @store_a = Marketplace::Store.create!(owner: @seller_a, name: "Buy Box A", slug: "buybox-a-#{SecureRandom.hex(3)}")
    @store_b = Marketplace::Store.create!(owner: @seller_b, name: "Buy Box B", slug: "buybox-b-#{SecureRandom.hex(3)}")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def offer(user:, store:, price:, delivery:, performance:, stock:, fulfilment:)
    Marketplace::Listing.create!(
      user: user, store: store, category: @category,
      title: "Shared model", price_cents: price, stock: stock,
      delivery_promise: delivery, seller_score: performance,
      fulfilment_method: fulfilment, buy_box_key: " ean  0123 "
    )
  end

  test "scores only shop offers sharing an explicit key and city" do
    slower = offer(user: @seller_a, store: @store_a, price: 4_000, delivery: 5, performance: 0.20, stock: 1, fulfilment: 0)
    faster = offer(user: @seller_b, store: @store_b, price: 4_500, delivery: 0, performance: 0.95, stock: 10, fulfilment: 1)

    result = Marketplace::BuyBoxSelector.for(slower)

    assert_equal faster.id, result.winner.id
    assert_equal [faster.id, slower.id], result.offers.map(&:id)
    assert_includes result.reasons_for(slower).join(" "), "delivery"
    assert_equal "EAN 0123", slower.reload.buy_box_key
  end

  test "does not compare private classifieds or a listing with no key" do
    shop_offer = offer(user: @seller_a, store: @store_a, price: 4_000, delivery: 2, performance: 0.8, stock: 3, fulfilment: 1)
    private_offer = Marketplace::Listing.create!(
      user: @seller_b, category: @category, title: "Shared model private",
      price_cents: 1_000, buy_box_key: "EAN 0123", stock: 1
    )

    result = Marketplace::BuyBoxSelector.for(shop_offer)

    assert_equal [shop_offer.id], result.offers.map(&:id)
    assert_nil private_offer.reload.buy_box_key
    assert_nil Marketplace::BuyBoxSelector.for(private_offer)
  end

  test "does not select offers from another city" do
    first = offer(user: @seller_a, store: @store_a, price: 4_000, delivery: 2, performance: 0.8, stock: 3, fulfilment: 1)
    other_city = City.where.not(id: @city.id).first || City.create!(name: "Other Buy Box City", slug: "other-buybox-city", domain: "other-buybox.test", country_code: "NO", locale: "nb", currency: "NOK")
    seller = User.strict_loading(false).create!(email_address: "buybox-c-#{SecureRandom.hex(3)}@brgen.no", password: "password123", city: other_city)
    store = ActsAsTenant.without_tenant do
      Marketplace::Store.create!(owner: seller, name: "Other City Shop", slug: "other-buybox-#{SecureRandom.hex(3)}", city: other_city)
    end
    ActsAsTenant.without_tenant do
      Marketplace::Listing.create!(
        user: seller, store: store, category: @category, city: other_city,
        title: "Shared model", price_cents: 1_000, stock: 5,
        buy_box_key: "EAN 0123", delivery_promise: 0
      )
    end

    assert_equal [first.id], Marketplace::BuyBoxSelector.for(first).offers.map(&:id)
  end
end
