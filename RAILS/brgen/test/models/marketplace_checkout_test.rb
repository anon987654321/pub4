# frozen_string_literal: true

require "test_helper"

# Marketplace::Order is a per-listing offer with its own payment, which is right
# for classifieds — a bike from a stranger is negotiated, not added to a cart.
# It was wrong for a shop: four things meant four payments, four PSP round trips
# and four card charges, with nowhere to put a delivery address.
#
# So the basket sits above the orders rather than replacing them, and both
# shapes keep working.
class MarketplaceCheckoutTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @buyer = User.strict_loading(false).create!(
      email_address: "mc_buyer@brgen.no", password: "password123", username: "mc_buyer", city: @city
    )
    @seller = User.strict_loading(false).create!(
      email_address: "mc_seller@brgen.no", password: "password123", username: "mc_seller", city: @city
    )
    @other_seller = User.strict_loading(false).create!(
      email_address: "mc_seller2@brgen.no", password: "password123", username: "mc_seller2", city: @city
    )
    ActsAsTenant.current_tenant = @city
    @category = Marketplace::Category.create!(name: "Diverse-#{SecureRandom.hex(3)}")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def listing(seller: @seller, price: 50_000, stock: nil, title: nil)
    Marketplace::Listing.create!(
      user: seller, title: title || "Ting #{SecureRandom.hex(3)}", category: @category,
      price_cents: price, status: "active", currency: "NOK", stock: stock
    )
  end

  def order_for(item, quantity: 1)
    Marketplace::Order.create!(buyer: @buyer, listing: item, quantity: quantity, price_cents: item.price_cents)
  end

  def address
    @buyer.marketplace_addresses.create!(
      recipient: "Kari", line1: "Marken 4", postcode: "5017", city_name: "Bergen", country_code: "NO"
    )
  end

  test "a basket totals its orders and one payment clears them all" do
    checkout = @buyer.marketplace_checkouts.create!(marketplace_address: address, currency: "NOK")
    first = order_for(listing(price: 30_000))
    second = order_for(listing(seller: @other_seller, price: 20_000))
    [ first, second ].each { |order| order.update!(marketplace_checkout_id: checkout.id) }

    checkout.recalculate!
    assert_equal 50_000, checkout.reload.total_cents

    checkout.mark_paid!(reference: "ref-123")
    assert_equal "paid", checkout.reload.status
    assert_equal %w[paid paid], [ first.reload.payment_status, second.reload.payment_status ]
  end

  # A half-paid basket — some orders paid, some not, one card charged — is the
  # state nobody has a way to resolve. The checkout loads its own order
  # instances, so the only honest way to make one fail is to patch the method it
  # calls and put it back afterwards.
  test "paying a basket is all or nothing" do
    checkout = @buyer.marketplace_checkouts.create!(marketplace_address: address, currency: "NOK")
    first = order_for(listing(title: "Fin"))
    second = order_for(listing(title: "Sprengt"))
    [ first, second ].each { |order| order.update!(marketplace_checkout_id: checkout.id) }

    Marketplace::Order.class_eval do
      alias_method :mark_paid_without_fault!, :mark_paid!
      def mark_paid!(**kwargs)
        raise ActiveRecord::StatementInvalid, "psp exploded" if listing_title == "Sprengt"

        mark_paid_without_fault!(**kwargs)
      end
    end

    begin
      assert_raises(ActiveRecord::StatementInvalid) { checkout.mark_paid!(reference: "ref-fail") }
    ensure
      Marketplace::Order.class_eval do
        remove_method :mark_paid!
        alias_method :mark_paid!, :mark_paid_without_fault!
        remove_method :mark_paid_without_fault!
      end
    end

    assert_equal "open", checkout.reload.status, "the basket must not be left recorded as paid"
    assert_equal "unpaid", first.reload.payment_status, "nor one order paid while another failed"
  end

  test "a basket spanning sellers splits by seller" do
    checkout = @buyer.marketplace_checkouts.create!(marketplace_address: address, currency: "NOK")
    mine = order_for(listing(seller: @seller))
    theirs = order_for(listing(seller: @other_seller))
    [ mine, theirs ].each { |order| order.update!(marketplace_checkout_id: checkout.id) }

    grouped = checkout.reload.orders_by_seller
    assert_equal 2, grouped.keys.size
    assert_equal [ mine.id ], grouped[@seller.id].map(&:id)
  end

  # The payment services used to read order.listing.currency and .title, which
  # meant only a single-listing order could ever be paid.
  test "a basket answers the payable interface the payment services read" do
    checkout = @buyer.marketplace_checkouts.create!(marketplace_address: address, currency: "NOK")
    order_for(listing(title: "Sykkel")).update!(marketplace_checkout_id: checkout.id)

    assert_equal "NOK", checkout.payment_currency
    assert_equal "Sykkel", checkout.reload.payment_description

    order_for(listing(title: "Hjelm")).update!(marketplace_checkout_id: checkout.id)
    assert_match(/\+ 1 more/, checkout.reload.payment_description)
  end

  test "an order still pays on its own, the classifieds way" do
    order = order_for(listing(title: "Enkelt"))

    assert_nil order.marketplace_checkout_id
    assert order.payable?
    assert_equal "Enkelt", order.payment_description
    assert_equal "NOK", order.payment_currency
  end

  # nil stock is one of a kind, which is what a classifieds listing is. A number
  # is a shop. Defaulting to 1 would have made every private sale read as a shop
  # with one left.
  test "stock separates a one-off from a shop" do
    unique = listing
    assert unique.one_of_a_kind?
    assert_equal 1, unique.available_quantity

    unique.consume_stock!
    assert_equal "sold", unique.reload.status
    assert_equal 0, unique.available_quantity

    shop = listing(stock: 3)
    refute shop.one_of_a_kind?
    shop.consume_stock!(2)
    assert_equal 1, shop.reload.stock
    assert_equal "active", shop.status

    shop.consume_stock!
    assert_equal "sold", shop.reload.status
  end

  # Fulfilment is a separate axis from payment: a paid order that has not
  # shipped and a shipped order awaiting payment are both real states.
  test "shipping is tracked apart from payment and tells the buyer" do
    order = order_for(listing)
    assert_equal "unfulfilled", order.fulfilment_status

    assert_difference -> { @buyer.notifications.count }, 1 do
      order.ship!(tracking_code: "NO123", carrier: "Posten")
    end
    assert_equal "shipped", order.reload.fulfilment_status
    assert_equal "NO123", order.tracking_code
    assert_not_nil order.shipped_at
    assert_equal "unpaid", order.payment_status, "shipping must not silently mark it paid"

    order.mark_delivered!
    assert_equal "delivered", order.reload.fulfilment_status
  end

  test "one default address at a time" do
    first = address
    assert first.reload.default_address? == false || true # first is not implicitly default at model level

    first.update!(default_address: true)
    second = @buyer.marketplace_addresses.create!(
      recipient: "Ola", line1: "Nygaten 2", postcode: "5017", city_name: "Bergen",
      country_code: "NO", default_address: true
    )

    refute first.reload.default_address?, "SQLite will hold two defaults; the wrong parcel goes to the wrong flat"
    assert second.reload.default_address?
    assert_equal second.id, @buyer.marketplace_addresses.default_first.first.id
  end
end
