# frozen_string_literal: true

require "test_helper"

class Marketplace::VariantOptionTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @category = Marketplace::Category.create!(name: "Kategori #{SecureRandom.hex(4)}")
    @seller = User.strict_loading(false).create!(
      email_address: "option_seller@brgen.no", password: "password123", city: @city
    )
    listing = ActsAsTenant.with_tenant(@city) do
      Marketplace::Listing.create!(
        category: @category, user: @seller, title: "Skjorte", price_cents: 299_00, currency: "NOK"
      )
    end
    @variant = Marketplace::Variant.create!(listing: listing)
    @other = Marketplace::Variant.create!(listing: listing)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a variant varies along each axis once" do
    Marketplace::VariantOption.create!(variant: @variant, name: "Størrelse", value: "M")
    again = Marketplace::VariantOption.new(variant: @variant, name: "Størrelse", value: "L")

    assert_not again.valid?
    assert again.errors.added?(:name, :taken, value: "Størrelse")
    assert Marketplace::VariantOption.new(variant: @other, name: "Størrelse", value: "L").valid?
  end

  test "an option needs both an axis and a point on it, each bounded" do
    blank = Marketplace::VariantOption.new(variant: @variant, name: "", value: "")
    long = Marketplace::VariantOption.new(variant: @variant, name: "x" * 41, value: "y" * 61)

    assert_not blank.valid?
    assert blank.errors.added?(:name, :blank)
    assert blank.errors.added?(:value, :blank)
    assert_not long.valid?
    assert long.errors.added?(:name, :too_long, count: 40)
    assert long.errors.added?(:value, :too_long, count: 60)
  end
end
