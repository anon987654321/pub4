# frozen_string_literal: true

require "test_helper"

class Marketplace::ListingFavoriteTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @category = Marketplace::Category.create!(name: "Kategori #{SecureRandom.hex(4)}")
    @seller = User.strict_loading(false).create!(
      email_address: "fav_seller@brgen.no", password: "password123", city: @city
    )
    @reader = User.strict_loading(false).create!(
      email_address: "fav_reader@brgen.no", password: "password123", city: @city
    )
    @other = User.strict_loading(false).create!(
      email_address: "fav_other@brgen.no", password: "password123", city: @city
    )
    @listing = ActsAsTenant.with_tenant(@city) do
      Marketplace::Listing.create!(
        category: @category, user: @seller, title: "Sykkel", price_cents: 1_000_00, currency: "NOK"
      )
    end
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a reader saves a listing once" do
    Marketplace::ListingFavorite.create!(user: @reader, listing: @listing)
    again = Marketplace::ListingFavorite.new(user: @reader, listing: @listing)

    assert_not again.valid?
    assert again.errors.added?(:user_id, :taken, value: @reader.id)
  end

  test "two readers may save the same listing" do
    Marketplace::ListingFavorite.create!(user: @reader, listing: @listing)

    assert Marketplace::ListingFavorite.new(user: @other, listing: @listing).valid?
  end
end
