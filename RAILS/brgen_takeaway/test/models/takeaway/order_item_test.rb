# frozen_string_literal: true

require "test_helper"

class Takeaway::OrderItemTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(email_address: "item_owner@brgen.no",
                                                password: "password123", city: @city)
    @buyer = User.strict_loading(false).create!(email_address: "item_buyer@brgen.no",
                                                password: "password123", city: @city)
    @restaurant = ActsAsTenant.with_tenant(@city) do
      Takeaway::Restaurant.create!(user: @owner, name: "Linjekjøkken", address: "Torget 2",
                                   cuisine_type: "Norwegian", city: @city, active: true)
    end
    @dish = Takeaway::MenuItem.create!(restaurant: @restaurant, name: "Lapskaus", price_cents: 150_00)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a line needs a quantity above zero" do
    ActsAsTenant.with_tenant(@city) do
      line = build_line(quantity: 0)

      assert_not line.valid?
      assert line.errors.added?(:quantity, :greater_than, value: 0, count: 0)
    end
  end

  test "a dish that is sold out, or from a closed restaurant, cannot be ordered" do
    ActsAsTenant.with_tenant(@city) do
      @dish.update!(available: false)
      assert build_line.tap(&:valid?).errors.added?(:menu_item, :unavailable)

      @dish.update!(available: true)
      @restaurant.update!(active: false)
      assert build_line.tap(&:valid?).errors.added?(:menu_item, :unavailable)
    end
  end

  # A controller builds a line from a dish it found by id, with nothing preloaded.
  test "a line built from a dish found by id validates without a lazy read" do
    ActsAsTenant.with_tenant(@city) do
      line = build_line(menu_item: Takeaway::MenuItem.find(@dish.id))

      assert line.valid?, line.errors.full_messages.to_sentence
    end
  end

  test "the subtotal is the unit price at the time of ordering times the quantity" do
    line = Takeaway::OrderItem.new(menu_item: @dish, quantity: 3, unit_price_cents: 120_00)

    assert_equal 360_00, line.subtotal_cents
    assert_equal Shared::MoneyDisplay.format(360_00), line.subtotal_display
  end

  private

  def build_line(menu_item: @dish, quantity: 1)
    order = Takeaway::Order.new(user: @buyer, restaurant: @restaurant, delivery_address: "Torget 1")
    Takeaway::OrderItem.new(order: order, menu_item: menu_item, quantity: quantity, unit_price_cents: menu_item.price_cents)
  end
end
