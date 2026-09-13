# frozen_string_literal: true

require "test_helper"

class Marketplace::HousingDetailTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @category = Marketplace::Category.create!(name: "Kategori #{SecureRandom.hex(4)}")
    @lister = User.strict_loading(false).create!(
      email_address: "housing_detail@brgen.no", password: "password123", city: @city
    )
    @listing = ActsAsTenant.with_tenant(@city) do
      Marketplace::Listing.create!(category: @category, user: @lister, title: "Hybel på Møhlenpris", kind: "housing")
    end
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a housing advert must state its rent" do
    detail = Marketplace::HousingDetail.new(listing: @listing, rooms: 2)

    assert_not detail.valid?
    assert detail.errors.added?(:rent_cents, :blank)
  end

  test "the housing type is one the form offers" do
    detail = Marketplace::HousingDetail.new(listing: @listing, rent_cents: 8_000_00, housing_type: "castle")

    assert_not detail.valid?
    assert detail.errors.added?(:housing_type, :inclusion, value: "castle")
    assert Marketplace::HousingDetail.new(listing: @listing, rent_cents: 8_000_00, housing_type: "").valid?
  end

  test "rooms and size must be positive and a deposit cannot be negative" do
    detail = Marketplace::HousingDetail.new(listing: @listing, rent_cents: 8_000_00,
                                            rooms: 0, size_sqm: 0, deposit_cents: -1)

    assert_not detail.valid?
    assert detail.errors.added?(:rooms, :greater_than, value: 0, count: 0)
    assert detail.errors.added?(:size_sqm, :greater_than, value: 0, count: 0)
    assert detail.errors.added?(:deposit_cents, :greater_than_or_equal_to, value: -1, count: 0)
  end

  test "rent always displays and a missing deposit does not" do
    detail = Marketplace::HousingDetail.new(rent_cents: 8_000_00)

    assert_equal Shared::MoneyDisplay.format(8_000_00), detail.rent_display
    assert_nil detail.deposit_display
  end
end
