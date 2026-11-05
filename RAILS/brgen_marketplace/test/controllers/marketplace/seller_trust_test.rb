# frozen_string_literal: true

require "test_helper"

# A private seller's buy box says what a buyer can know about a stranger:
# member since, completed sales, and a proved identity when there is one. A
# shop's listing does not carry it.
class Marketplace::SellerTrustTest < ActionDispatch::IntegrationTest
  setup do
    host! "markedsplass.brgen.no"
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    @seller = User.create!(email_address: "st_seller_#{SecureRandom.hex(3)}@example.com", password: "secret1234")
    @seller.update_columns(created_at: Time.zone.local(2024, 3, 10))
    @buyer = User.create!(email_address: "st_buyer_#{SecureRandom.hex(3)}@example.com", password: "secret1234")
    @category = Marketplace::Category.create!(name: "Probe", slug: "st-#{SecureRandom.hex(4)}")
    @listing = Marketplace::Listing.create!(user: @seller, category: @category, title: "Sykkel", price_cents: 150_000, stock: 3)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def facts
    get marketplace.listing_path(@listing)
    Nokogiri::HTML(response.body).at_css("ul.seller-trust")&.text.to_s.squish
  end

  test "a private seller's box names member since and completed sales" do
    sold = @listing.orders.create!(buyer: @buyer, price_cents: 150_000, quantity: 1)
    sold.update!(payment_status: "paid", status: "paid", fulfilment_status: "delivered")
    @listing.orders.create!(buyer: @buyer, price_cents: 150_000, quantity: 1)

    text = facts
    assert_includes text, I18n.t("marketplace.seller_member_since", date: I18n.l(Date.new(2024, 3, 10), format: "%B %Y"))
    assert_includes text, I18n.t("marketplace.seller_completed_sales", count: 1)
    refute_includes text, I18n.t("marketplace.seller_identity_verified")
  end

  test "a Vipps-proved seller says so" do
    vipps = IdentityProvider.find_by(slug: "vipps") || IdentityProvider.create!(slug: "vipps", name: "Vipps")
    ExternalIdentity.create!(user: @seller, identity_provider: vipps, subject: "sub-#{SecureRandom.hex(3)}", assurance_level: "verified")

    assert_includes facts, I18n.t("marketplace.seller_identity_verified")
  end

  test "a shop's listing carries no private-seller facts" do
    store = Marketplace::Store.create!(owner: @seller, name: "Butikk #{SecureRandom.hex(2)}", slug: "st-#{SecureRandom.hex(4)}")
    @listing.update!(store: store)

    assert_empty facts
  end
end
