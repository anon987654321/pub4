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