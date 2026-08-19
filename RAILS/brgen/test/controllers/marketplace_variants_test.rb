# frozen_string_literal: true

require "test_helper"

# marketplace_listings.stock is the right answer for a bike and the wrong one
# for a shirt in four sizes: the shop either lists it four times or oversells
# the medium.
class MarketplaceVariantsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @seller = create_user("mv_seller")
    @buyer = create_user("mv_buyer")
    ActsAsTenant.current_tenant = @city
    @category = Marketplace::Category.create!(name: "Klær", slug: "klaer-#{SecureRandom.hex(4)}")
    @listing = Marketplace::Listing.create!(user: @seller, category: @category, title: "Ullgenser #{SecureRandom.hex(2)}",
                                            price_cents: 90_000, stock: 5)
    @medium = variant(size: "M", stock: 2)
    @large = variant(size: "L", stock: 0, price_cents: 100_000)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def variant(size:, **attrs)
    v = @listing.variants.create!(**attrs)
    v.options.create!(name: "Størrelse", value: size)
    v
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "markedsplass.brgen.no"
  end

  test "a variant prices itself, or inherits the listing's" do
    assert_equal 90_000, @medium.price_cents_or_listing
    assert_equal 100_000, @large.price_cents_or_listing
    assert_equal "M", @medium.label
  end

  # The thing variants exist to stop: four sizes sharing one count.
  test "stock is the variant's own" do
    assert_predicate @medium, :in_stock?
    assert_not_predicate @large, :in_stock?

    @medium.consume_stock!(2)
    assert_equal 0, @medium.reload.stock
    assert_equal 5, @listing.reload.stock
  end

  test "an order on a listing with versions must name one" do
    order = @listing.orders.build(buyer: @buyer, price_cents: 90_000, quantity: 1)
    assert_not order.valid?
    assert_includes order.errors.attribute_names, :variant

    order.variant = @medium
    assert_predicate order, :valid?
  end

  test "a variant from another listing is refused" do
    other = Marketplace::Listing.create!(user: @seller, category: @category, title: "Annen #{SecureRandom.hex(2)}", price_cents: 1_000)
    stray = other.variants.create!
    stray.options.create!(name: "Størrelse", value: "S")

    order = @listing.orders.build(buyer: @buyer, variant: stray, price_cents: 90_000, quantity: 1)
    assert_not order.valid?
  end

  test "paying consumes the variant's stock, not the listing's" do
    order = @listing.orders.create!(buyer: @buyer, variant: @medium, price_cents: 90_000, quantity: 1)

    order.mark_paid!(reference: "test-#{SecureRandom.hex(3)}")

    assert_equal 1, @medium.reload.stock
    assert_equal 5, @listing.reload.stock
  end

  test "the seller adds and removes a version" do
    sign_in_as(@seller)

    assert_difference -> { Marketplace::Variant.count }, 1 do
      post marketplace.listing_variants_path(@listing), params: {
        variant: { option_one_name: "Størrelse", option_one_value: "S",
                               option_two_name: "Farge", option_two_value: "Blå", stock: 3 }
      }
    end
    added = Marketplace::Variant.order(:created_at).last
    assert_equal "Blå · S", added.label

    delete marketplace.listing_variant_path(@listing, added)
    assert_not Marketplace::Variant.exists?(added.id)
  end

  # An order is the buyer's receipt, and retiring a size does not own the
  # buyer's half of it.
  test "a version with orders against it stays" do
    @listing.orders.create!(buyer: @buyer, variant: @medium, price_cents: 90_000, quantity: 1)
    sign_in_as(@seller)

    delete marketplace.listing_variant_path(@listing, @medium)
    assert Marketplace::Variant.exists?(@medium.id)
  end

  test "only the seller edits the versions" do
    sign_in_as(@buyer)

    get marketplace.listing_variants_path(@listing)
    assert_response :forbidden
  end

  test "the listing page offers the versions in stock" do
    sign_in_as(@buyer)

    get marketplace.listing_path(@listing)
    assert_response :success
    assert_includes response.body, "order[variant_id]"
    assert_includes response.body, "M —"
  end
end
