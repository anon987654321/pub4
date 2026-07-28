# frozen_string_literal: true

require "test_helper"

class Takeaway::OrderTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(email_address: "restaurant@brgen.no", password: "password123", city: @city)
    @buyer = User.strict_loading(false).create!(email_address: "hungry@brgen.no", password: "password123", city: @city)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  # Same defect class as Marketplace::Order#seller: the lifecycle tests below
  # pass only because the order is built with its restaurant and user already in
  # memory. Anything that loads an order from the database first — a controller
  # action, a driver app request, a job — gets none of that preloaded, and every
  # model here is strict_loading by default (shared ApplicationRecord) with
  # production raising on a violation. transition_to! reads `user`,
  # `restaurant.name` and `restaurant.user`, so it would raise *after* update!
  # had already committed the new status: the order advances, the customer is
  # never notified, and the caller sees a 500.
  test "transition_to! on a freshly-found order does not violate strict loading" do
    ActsAsTenant.with_tenant(@city) do
      restaurant = Takeaway::Restaurant.create!(
        user: @owner, name: "Strict Kitchen", address: "Marken 4",
        cuisine_type: "Norwegian", city: @city
      )
      created = Takeaway::Order.create!(
        user: @buyer, restaurant: restaurant,
        delivery_address: "Nordnesveien 2", status: "pending"
      )

      bare = Takeaway::Order.find_by(id: created.id)
      refute bare.association(:restaurant).loaded?, "guard: restaurant must NOT be preloaded or this proves nothing"

      assert bare.confirm!
      assert_equal "confirmed", created.reload.status
    end
  end

  test "calculate_totals! on a freshly-found order does not violate strict loading" do
    ActsAsTenant.with_tenant(@city) do
      restaurant = Takeaway::Restaurant.create!(
        user: @owner, name: "Totals Kitchen", address: "Marken 6",
        cuisine_type: "Norwegian", city: @city, delivery_fee_cents: 4_900,
        # OrderItem validates menu_item.available_for_order?, which requires the
        # restaurant to be active.
        active: true
      )
      item = Takeaway::MenuItem.create!(restaurant: restaurant, name: "Fiskesuppe", price_cents: 18_900, available: true)
      created = Takeaway::Order.create!(
        user: @buyer, restaurant: restaurant,
        delivery_address: "Nordnesveien 4", status: "pending"
      )
      created.order_items.create!(menu_item: item, quantity: 2, unit_price_cents: item.price_cents)

      bare = Takeaway::Order.includes(:order_items).find_by(id: created.id)
      bare.calculate_totals!

      assert_equal 37_800, created.reload.subtotal_cents
      assert_equal 4_900, created.delivery_fee_cents
      assert_equal 42_700, created.total_cents
    end
  end

  test "advances through placed to delivered lifecycle" do
    ActsAsTenant.with_tenant(@city) do
      restaurant = Takeaway::Restaurant.create!(
        user: @owner,
        name: "Fjord Kitchen",
        address: "Bryggen 1",
        cuisine_type: "Norwegian",
        city: @city
      )
      order = Takeaway::Order.create!(
        user: @buyer,
        restaurant: restaurant,
        delivery_address: "Kong Oscars gate 1",
        status: "pending"
      )

      assert order.confirm!
      assert order.prepare!
      assert order.dispatch!
      assert order.deliver!

      assert_equal "delivered", order.reload.status
    end
  end

  test "rejects invalid status transition" do
    ActsAsTenant.with_tenant(@city) do
      restaurant = Takeaway::Restaurant.create!(
        user: @owner,
        name: "Harbor Grill",
        address: "Havnen 2",
        cuisine_type: "Pizza",
        city: @city
      )
      order = Takeaway::Order.create!(
        user: @buyer,
        restaurant: restaurant,
        delivery_address: "Torget 3",
        status: "pending"
      )

      assert_not order.transition_to!("delivered")
      assert_includes order.errors[:status], "cannot transition from pending to delivered"
    end
  end
end
