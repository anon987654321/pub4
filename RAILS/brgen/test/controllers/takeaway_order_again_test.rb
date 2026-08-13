# frozen_string_literal: true

require "test_helper"

class TakeawayOrderAgainTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @owner = User.strict_loading(false).create!(
      email_address: "again_owner@brgen.no", password: "password123",
      username: "again_owner", guest: false, city: @city
    )
    @buyer = User.strict_loading(false).create!(
      email_address: "again_buyer@brgen.no", password: "password123",
      username: "again_buyer", guest: false, city: @city
    )
    @restaurant = Takeaway::Restaurant.create!(
      user: @owner, name: "Again Kitchen", address: "Marken 40",
      cuisine_type: "Norwegian", city: @city, active: true, min_order_cents: 0
    )
    @soup = Takeaway::MenuItem.create!(
      restaurant: @restaurant, name: "Fiskesuppe", price_cents: 18_900, available: true
    )
    @bread = Takeaway::MenuItem.create!(
      restaurant: @restaurant, name: "Brød", price_cents: 3_000, available: true
    )
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  def placed_order
    order = @restaurant.orders.build(
      user: @buyer, delivery_address: "Torget 8", special_instructions: "Ingen løk"
    )
    order.order_items.build(menu_item: @soup, quantity: 2, unit_price_cents: @soup.price_cents)
    order.order_items.build(menu_item: @bread, quantity: 1, unit_price_cents: @bread.price_cents)
    order.save!
    order.calculate_totals!
    order
  end

  test "again copies available items and the same address onto a new order" do
    source = placed_order
    sign_in_as(@buyer)
    host! "takeaway.brgen.no"

    assert_difference -> { Takeaway::Order.count }, 1 do
      post takeaway.again_order_path(source)
    end
    copy = Takeaway::Order.order(:id).last
    assert_redirected_to takeaway.order_path(copy)
    assert_equal @buyer.id, copy.user_id
    assert_equal "Torget 8", copy.delivery_address
    assert_equal "Ingen løk", copy.special_instructions
    assert_equal "pending", copy.status
    assert_equal 2, copy.order_items.find_by!(menu_item: @soup).quantity
    assert_equal 1, copy.order_items.find_by!(menu_item: @bread).quantity
    refute_equal source.id, copy.id
  end

  test "again skips items that left the menu and refuses an empty copy" do
    source = placed_order
    @soup.update!(available: false)
    @bread.update!(available: false)
    sign_in_as(@buyer)
    host! "takeaway.brgen.no"

    assert_no_difference -> { Takeaway::Order.count } do
      post takeaway.again_order_path(source)
    end
    assert_redirected_to takeaway.restaurant_path(@restaurant)
  end

  test "the order page posts to again rather than linking at the restaurant" do
    source = placed_order
    sign_in_as(@buyer)
    host! "takeaway.brgen.no"

    get takeaway.order_path(source)
    assert_response :success
    assert_match(/again/, response.body)
    refute_match(%r{href="[^"]*#{Regexp.escape(takeaway.restaurant_path(@restaurant))}"[^>]*>#{Regexp.escape(I18n.t("actions.reorder"))}},
                 response.body)
  end
end
