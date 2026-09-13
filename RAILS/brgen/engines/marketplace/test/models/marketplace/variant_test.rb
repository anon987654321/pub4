# frozen_string_literal: true

require "test_helper"

class Marketplace::VariantTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @category = Marketplace::Category.create!(name: "Kategori #{SecureRandom.hex(4)}")
    @seller = User.strict_loading(false).create!(
      email_address: "variant_seller@brgen.no", password: "password123", city: @city
    )
    @listing = ActsAsTenant.with_tenant(@city) do
      Marketplace::Listing.create!(
        category: @category, user: @seller, title: "Genser", price_cents: 499_00, currency: "NOK"
      )
    end
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "price and stock cannot be negative and the sku is bounded" do
    variant = Marketplace::Variant.new(listing: @listing, price_cents: -1, stock: -1, sku: "x" * 61)

    assert_not variant.valid?
    assert variant.errors.added?(:price_cents, :greater_than_or_equal_to, value: -1, count: 0)
    assert variant.errors.added?(:stock, :greater_than_or_equal_to, value: -1, count: 0)
    assert variant.errors.added?(:sku, :too_long, count: 60)
  end

  test "a variant found by id inherits the listing's price when it has none" do
    id = Marketplace::Variant.create!(listing: @listing).id

    assert_equal 499_00, Marketplace::Variant.find(id).price_cents_or_listing
  end

  test "consuming stock counts down and stops at zero" do
    variant = Marketplace::Variant.create!(listing: @listing, stock: 2)

    variant.consume_stock!(3)

    assert_equal 0, variant.reload.stock
    assert_not variant.in_stock?
    assert_raises(RuntimeError) { variant.consume_stock! }
  end

  test "a variant with no stock count is one of a kind and never runs out" do
    variant = Marketplace::Variant.create!(listing: @listing, stock: nil)

    variant.consume_stock!(5)

    assert_nil variant.reload.stock
    assert variant.unlimited_stock?
  end

  test "in_stock holds unlimited and positive stock, not zero" do
    unlimited = Marketplace::Variant.create!(listing: @listing, stock: nil)
    some = Marketplace::Variant.create!(listing: @listing, stock: 3)
    none = Marketplace::Variant.create!(listing: @listing, stock: 0)

    assert_equal [ unlimited.id, some.id ].sort, @listing.variants.in_stock.pluck(:id).sort
    assert_not_includes Marketplace::Variant.in_stock, none
  end

  test "the label is built from the options, sorted by axis, or falls back to the sku" do
    options = [ { name: "Størrelse", value: "M" }, { name: "Farge", value: "Blå" } ]
    variant = Marketplace::Variant.create!(listing: @listing, sku: "GENSER-M", options_attributes: options)
    bare = Marketplace::Variant.create!(listing: @listing, sku: "GENSER-L")

    assert_equal "Blå · M", Marketplace::Variant.includes(:options).find(variant.id).label
    assert_equal "GENSER-L", Marketplace::Variant.includes(:options).find(bare.id).label
  end
end
