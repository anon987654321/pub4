# frozen_string_literal: true

require "test_helper"

# A basket paid with Vipps carried the reference "brgen-order-{basket id}", and
# the webhook read that number as an order id: it paid an unrelated order that
# shared the id, or nothing, and the basket stayed pending.
class VippsReferenceTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    @buyer = User.strict_loading(false).create!(
      email_address: "vr-#{SecureRandom.hex(4)}@brgen.no", password: "password123", guest: false
    )
    category = Marketplace::Category.create!(name: "Diverse-#{SecureRandom.hex(3)}")
    @listing = Marketplace::Listing.create!(
      user: User.create!(email_address: "vs-#{SecureRandom.hex(4)}@brgen.no", password: "password123"),
      title: "Ting #{SecureRandom.hex(3)}", category:,
      price_cents: 20_000, status: "active", currency: "NOK"
    )
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "a basket's reference finds the basket, not an order that shares its id" do
    basket = Marketplace::Checkout.create!(user: @buyer, status: "pending_payment")
    reference = "brgen-order-#{basket.id}-beef"
    basket.update_columns(payment_reference: reference)
    Marketplace::Order.create!(id: basket.id, buyer: @buyer, listing: @listing, quantity: 1, price_cents: 20_000)

    assert_equal basket, Webhooks::PaymentPaid.find_order_from_vipps_reference(reference)
  end

  test "new references name the table their id belongs to" do
    basket = Marketplace::Checkout.create!(user: @buyer, status: "open")
    assert_match(/\Abrgen-checkout-#{basket.id}-\h{8}\z/, Marketplace::Payments::VippsCheckout.reference_for(basket))
    order = Marketplace::Order.create!(buyer: @buyer, listing: @listing, quantity: 1, price_cents: 20_000)
    assert_match(/\Abrgen-order-#{order.id}-\h{8}\z/, Marketplace::Payments::VippsCheckout.reference_for(order))
  end

  test "an unstored reference falls back to the table it names" do
    basket = Marketplace::Checkout.create!(user: @buyer, status: "pending_payment")
    assert_equal basket, Webhooks::PaymentPaid.find_order_from_vipps_reference("brgen-checkout-#{basket.id}-cafe")
  end
end
