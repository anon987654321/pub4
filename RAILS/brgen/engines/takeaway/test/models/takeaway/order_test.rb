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
        cuisine_type: "Norwegian", city: @city, active: true
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
      # The key, not the sentence. default_locale is nb, so asserting the
      # English string tied this to whichever language the message was in --
      # and it was English on a Norwegian site, which was the bug (dfd59426b).
      assert_includes order.errors.details[:status].map { |d| d[:error] }, :bad_transition
    end
  end

  test "an order below the restaurant minimum is rejected at create" do
    ActsAsTenant.with_tenant(@city) do
      restaurant = Takeaway::Restaurant.create!(
        user: @owner, name: "Minimum Kitchen", address: "Marken 9",
        cuisine_type: "Norwegian", city: @city, active: true, min_order_cents: 15_000
      )
      item = Takeaway::MenuItem.create!(restaurant: restaurant, name: "Kaffe", price_cents: 3_000, available: true)

      order = restaurant.orders.build(user: @buyer, delivery_address: "Torget 1")
      order.order_items.build(menu_item: item, quantity: 1, unit_price_cents: item.price_cents)

      assert_not order.save, "30 kr order must not clear a 150 kr minimum"
      assert_includes order.errors.details[:base].map { |d| d[:error] }, :below_minimum
    end
  end

  test "an order meeting the minimum saves" do
    ActsAsTenant.with_tenant(@city) do
      restaurant = Takeaway::Restaurant.create!(
        user: @owner, name: "Just Enough", address: "Marken 11",
        cuisine_type: "Norwegian", city: @city, active: true, min_order_cents: 15_000
      )
      item = Takeaway::MenuItem.create!(restaurant: restaurant, name: "Middag", price_cents: 8_000, available: true)

      order = restaurant.orders.build(user: @buyer, delivery_address: "Torget 1")
      order.order_items.build(menu_item: item, quantity: 2, unit_price_cents: item.price_cents)

      assert order.save, order.errors.full_messages.join("; ")
    end
  end

  test "no minimum set imposes no floor" do
    ActsAsTenant.with_tenant(@city) do
      restaurant = Takeaway::Restaurant.create!(
        user: @owner, name: "No Floor", address: "Marken 13",
        cuisine_type: "Norwegian", city: @city, active: true
      )
      item = Takeaway::MenuItem.create!(restaurant: restaurant, name: "Snack", price_cents: 500, available: true)

      order = restaurant.orders.build(user: @buyer, delivery_address: "Torget 1")
      order.order_items.build(menu_item: item, quantity: 1, unit_price_cents: item.price_cents)

      assert order.save, order.errors.full_messages.join("; ")
    end
  end
end
