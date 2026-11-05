# frozen_string_literal: true

require "test_helper"

# Sellers type money in kroner. The forms used to ask for øre (25000 for
# NOK 250), and one missing zero listed a thing at a tenth of its price.
class Marketplace::ListingKronerFieldsTest < ActionDispatch::IntegrationTest
  setup do
    host! "markedsplass.brgen.no"
    @seller = User.create!(email_address: "kr_seller_#{SecureRandom.hex(3)}@example.com", password: "secret1234")
    @category = Marketplace::Category.create!(name: "Probe", slug: "kr-#{SecureRandom.hex(4)}")
    post session_path, params: { email_address: @seller.email_address, password: "secret1234" }
  end

  test "the parser reads kroner and refuses what is not an amount" do
    parse = Marketplace::KronerFields.method(:parse)
    assert_equal 25_000, parse.("250")
    assert_equal 25_050, parse.("250,50")
    assert_equal 25_050, parse.("250.5")
    assert_equal 125_000, parse.("1 250")
    assert_equal 125_000, parse.("1 250 kr")
    assert_nil parse.("")
    assert_equal :invalid, parse.("250,505")
    assert_equal :invalid, parse.("-5")
    assert_equal :invalid, parse.("abc")
  end

  test "the new listing form asks for kroner" do
    get marketplace.new_listing_path
    assert_select "input[name='listing[price_kroner]']"
    assert_select "input[name='listing[price_cents]']", count: 0
    assert_includes response.body, I18n.t("marketplace.price_kroner")
  end

  test "a price typed as 250,50 is stored as 25050 øre" do
    post marketplace.listings_path, params: {
      listing: { title: "Sykkelhjelm", kind: "goods", price_kroner: "250,50", category_id: @category.id }
    }

    assert_redirected_to %r{/listings/}
    assert_equal 25_050, Marketplace::Listing.order(:id).last.price_cents
  end

  test "a price that is not an amount is refused with the form" do
    assert_no_difference -> { Marketplace::Listing.count } do
      post marketplace.listings_path, params: {
        listing: { title: "Sykkelhjelm", kind: "goods", price_kroner: "tjue", category_id: @category.id }
      }
    end

    assert_response :unprocessable_entity
    assert_select "input[name='listing[price_kroner]'][value='tjue']"
  end

  test "rent and deposit are typed in kroner" do
    post marketplace.listings_path, params: {
      listing: { title: "Hybel", kind: "housing", category_id: @category.id,
                 housing_detail_attributes: { rent_kroner: "8 500", deposit_kroner: "25000" } }
    }

    detail = Marketplace::Listing.order(:id).last.housing_detail
    assert_equal 850_000, detail.rent_cents
    assert_equal 2_500_000, detail.deposit_cents
  end

  test "the edit form shows the stored price in kroner" do
    listing = Marketplace::Listing.create!(user: @seller, category: @category, title: "Stol", price_cents: 34_950)

    get marketplace.edit_listing_path(listing)

    assert_select "input[name='listing[price_kroner]'][value='349,50']"
  end
end
