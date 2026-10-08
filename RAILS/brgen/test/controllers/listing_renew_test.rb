# frozen_string_literal: true

require "test_helper"

class ListingRenewTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @seller = User.strict_loading(false).create!(
      email_address: "lr_seller@brgen.no", password: "password123", username: "lr_seller", guest: false, city: @city
    )
    @buyer = User.strict_loading(false).create!(
      email_address: "lr_buyer@brgen.no", password: "password123", username: "lr_buyer", guest: false, city: @city
    )
    @category = Marketplace::Category.create!(name: "Diverse-#{SecureRandom.hex(3)}")
    @listing = Marketplace::Listing.create!(
      user: @seller, title: "Stol #{SecureRandom.hex(3)}", category: @category,
      price_cents: 15_000, status: "active", currency: "NOK"
    )
    @listing.update_columns(expires_at: 1.hour.ago)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "the owner renews a lapsed listing from the listing page" do
    sign_in_as(@seller)
    host! "markedsplass.brgen.no"

    get marketplace.listing_path(@listing)
    assert_response :success
    assert_includes response.body, I18n.t("marketplace.expired_notice")
    assert_includes response.body, I18n.t("marketplace.renew")

    post marketplace.renew_listing_path(@listing)
    assert_redirected_to marketplace.listing_path(@listing)
    refute @listing.reload.expired?
    assert @listing.buyable?
  end

  test "a stranger cannot renew someone else's listing" do
    sign_in_as(@buyer)
    host! "markedsplass.brgen.no"

    post marketplace.renew_listing_path(@listing)
    assert_redirected_to marketplace.root_path
    assert @listing.reload.expired?
  end
end
