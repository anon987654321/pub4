# frozen_string_literal: true

require "test_helper"

class Takeaway::MenuCategoryTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(
      email_address: "menu_category_#{SecureRandom.hex(3)}@brgen.no",
      password: "password123",
      city: @city
    )
    @restaurant = ActsAsTenant.with_tenant(@city) do
      Takeaway::Restaurant.create!(
        user: @owner, name: "Category Kitchen", address: "Marken 4",
        cuisine_type: "Norwegian", city: @city, active: true
      )
    end
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "names are trimmed, bounded and unique within one restaurant" do
    category = @restaurant.menu_categories.create!(name: "  Middag  ")
    assert_equal "Middag", category.name

    duplicate = @restaurant.menu_categories.new(name: "middag")
    assert_not duplicate.valid?
    assert_includes duplicate.errors.details[:name].map { |detail| detail[:error] }, :taken

    other = Takeaway::Restaurant.create!(
      user: @owner, name: "Another Kitchen", address: "Marken 5",
      cuisine_type: "Norwegian", city: @city, active: true
    )
    assert other.menu_categories.create!(name: "Middag")
  end

  test "category names cannot exceed forty characters" do
    category = @restaurant.menu_categories.new(name: "x" * 41)

    assert_not category.valid?
    assert_includes category.errors.details[:name].map { |detail| detail[:error] }, :too_long
  end
end
