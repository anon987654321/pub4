# frozen_string_literal: true

require "test_helper"

class Takeaway::MenuItemTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(email_address: "menu_owner@brgen.no",
                                                password: "password123", city: @city)
    @restaurant = ActsAsTenant.with_tenant(@city) do
      Takeaway::Restaurant.create!(user: @owner, name: "Menykjøkken", address: "Marken 4",
                                   cuisine_type: "Norwegian", city: @city, active: true)
    end
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a dish needs a name and a price above zero" do
    blank = Takeaway::MenuItem.new(restaurant: @restaurant, name: "", price_cents: nil)
    free = Takeaway::MenuItem.new(restaurant: @restaurant, name: "Vann", price_cents: 0)

    assert_not blank.valid?
    assert blank.errors.added?(:name, :blank)
    assert blank.errors.added?(:price_cents, :blank)
    assert_not free.valid?
    assert free.errors.added?(:price_cents, :greater_than, value: 0, count: 0)
  end

  test "a dish saved without saying is available, and one marked unavailable stays so" do
    assert Takeaway::MenuItem.create!(restaurant: @restaurant, name: "Fiskesuppe", price_cents: 189_00).available?
    sold_out = Takeaway::MenuItem.create!(restaurant: @restaurant, name: "Klippfisk", price_cents: 245_00, available: false)

    assert_not sold_out.available?
    assert_not_includes Takeaway::MenuItem.available, sold_out
  end

  test "a dish found by id is orderable only while it and its restaurant are" do
    ActsAsTenant.with_tenant(@city) do
      id = Takeaway::MenuItem.create!(restaurant: @restaurant, name: "Raspeball", price_cents: 199_00).id

      assert Takeaway::MenuItem.find(id).available_for_order?
      @restaurant.update!(active: false)
      assert_not Takeaway::MenuItem.find(id).available_for_order?
    end
  end

  test "a dish found by id names its restaurant's owner" do
    id = Takeaway::MenuItem.create!(restaurant: @restaurant, name: "Persetorsk", price_cents: 229_00).id

    assert_equal @owner.id, Takeaway::MenuItem.find(id).restaurant_owner&.id
  end
end
