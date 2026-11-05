# frozen_string_literal: true

require "test_helper"

# The fourteen allergens on a dish: the kitchen states them, the diner reads
# them on the menu and the order form, and a dish nobody has checked says so.
# No allergen is ever filled in on the kitchen's behalf.
class TakeawayAllergensTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @owner = create_user("ta_owner")
    @diner = create_user("ta_diner")
    @restaurant = Takeaway::Restaurant.create!(
      user: @owner, name: "Kjøkkenet #{SecureRandom.hex(2)}", address: "Torget 2",
      cuisine_type: "Norwegian", city: @city, active: true, min_order_cents: 0
    )
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}_#{SecureRandom.hex(2)}@brgen.no", password: "password123",
      username: "#{name}_#{SecureRandom.hex(2)}", guest: false, city: @city
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "takeaway.brgen.no"
  end

  def add_dish(**allergen_params)
    post takeaway.restaurant_menu_items_path(@restaurant), params: {
      takeaway_menu_item: { name: "Fiskesuppe", price_cents: 18_900, available: "1" }.merge(allergen_params)
    }
    Takeaway::MenuItem.order(:id).last
  end

  test "the kitchen states a dish's allergens and the diner reads them" do
    sign_in_as(@owner)
    dish = add_dish(allergens: [ "", "milk", "fish", "made_up" ], allergens_stated: "1")
    assert_equal %w[fish milk], dish.allergen_keys

    sign_in_as(@diner)
    get takeaway.restaurant_path(@restaurant)
    names = %w[fish milk].map { I18n.t("takeaway.allergen_names.#{_1}") }.to_sentence
    assert_includes response.body, I18n.t("takeaway.allergens_list", list: names)

    get takeaway.new_restaurant_order_path(@restaurant)
    assert_includes response.body, I18n.t("takeaway.allergens_list", list: names)
  end

  test "a dish the kitchen has not checked says so, and the kitchen is told" do
    sign_in_as(@owner)
    dish = add_dish(allergens: [ "milk" ], allergens_stated: "0")
    assert_nil dish.allergens

    get takeaway.restaurant_path(@restaurant)
    assert_includes response.body, I18n.t("takeaway.allergens_unstated")
    assert_includes response.body, I18n.t("takeaway.allergens_owner_note", count: 1)
  end

  test "checked with no boxes ticked is none of the fourteen, not unstated" do
    sign_in_as(@owner)
    dish = add_dish(allergens: [ "" ], allergens_stated: "1")

    assert_equal [], dish.allergens
    get takeaway.restaurant_path(@restaurant)
    assert_includes response.body, I18n.t("takeaway.allergens_none")
  end

  test "the kitchen corrects a dish, and nobody else can" do
    dish = Takeaway::MenuItem.create!(restaurant: @restaurant, name: "Bolle", price_cents: 3_500)
    sign_in_as(@owner)
    patch takeaway.restaurant_menu_item_path(@restaurant, dish), params: {
      takeaway_menu_item: { allergens: [ "gluten", "eggs" ], allergens_stated: "1" }
    }
    assert_equal %w[gluten eggs], dish.reload.allergen_keys

    sign_in_as(@diner)
    patch takeaway.restaurant_menu_item_path(@restaurant, dish), params: {
      takeaway_menu_item: { allergens: [], allergens_stated: "1" }
    }
    assert_equal %w[gluten eggs], dish.reload.allergen_keys
  end
end
