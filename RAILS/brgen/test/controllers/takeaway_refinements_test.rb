# frozen_string_literal: true

require "test_helper"

# Takeaway orders and couriers: who may see an order, when a shut kitchen
# takes one, what the order form keeps and labels, and what the bill lists.
class TakeawayRefinementsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @owner = member("tr_owner")
    @diner = member("tr_diner")
    @restaurant = Takeaway::Restaurant.create!(
      user: @owner, name: "Refine Kitchen", address: "Marken 41",
      cuisine_type: "Norwegian", city: @city, active: true, min_order_cents: 0
    )
    @soup = Takeaway::MenuItem.create!(restaurant: @restaurant, name: "Fiskesuppe", price_cents: 18_900,
                                       available: true)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def member(handle)
    User.strict_loading(false).create!(
      email_address: "#{handle}@brgen.no", password: "password123", username: handle, guest: false, city: @city
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "takeaway.brgen.no"
  end

  def order_for(user, status: "pending", tip_cents: 0)
    order = @restaurant.orders.build(user:, delivery_address: "Torget 8", tip_cents:)
    order.order_items.build(menu_item: @soup, quantity: 1, unit_price_cents: @soup.price_cents)
    order.save!
    order.calculate_totals!
    order.update_columns(status:)
    order
  end

  # Open three days from today, 10:00-20:00, so the kitchen is shut now.
  def shut_now_open_later
    day = (Time.zone.now.wday + 3) % 7
    Takeaway::OpeningHour.create!(restaurant: @restaurant, weekday: day, opens_minute: 600, closes_minute: 1200)
    Time.zone.now.beginning_of_day + 3.days
  end

  def place(scheduled_for: nil)
    post takeaway.restaurant_orders_path(@restaurant), params: {
      takeaway_order: { delivery_address: "Torget 8", scheduled_for:, items: { @soup.id.to_s => "1" } }.compact
    }
  end

  test "a stranger cannot open another diner's order" do
    order = order_for(@diner)
    sign_in_as(member("tr_stranger"))

    get takeaway.order_path(order)
    assert_response :not_found
  end

  test "a shut kitchen refuses an order for now and for a time it is shut" do
    later = shut_now_open_later
    sign_in_as(@diner)

    assert_no_difference -> { Takeaway::Order.count } do
      place
      assert_redirected_to takeaway.restaurant_path(@restaurant)
      place(scheduled_for: (later + 22.hours).iso8601)
      assert_redirected_to takeaway.restaurant_path(@restaurant)
    end
    assert_equal I18n.t("flash.takeaway.closed_now"), flash[:alert]
  end

  test "a shut kitchen takes an order for a time it is open" do
    later = shut_now_open_later
    sign_in_as(@diner)

    assert_difference -> { Takeaway::Order.count }, 1 do
      place(scheduled_for: (later + 11.hours).iso8601)
    end
  end

  test "the order form names each dish's quantity and keeps it through an error" do
    sign_in_as(@diner)

    get takeaway.new_restaurant_order_path(@restaurant)
    assert_select "label[for=?]", "takeaway_order_items_#{@soup.id}", text: I18n.t("takeaway.qty_for", name: @soup.name)

    post takeaway.restaurant_orders_path(@restaurant),
         params: { takeaway_order: { delivery_address: "", items: { @soup.id.to_s => "2" } } }
    assert_response :unprocessable_entity
    assert_select "input#takeaway_order_items_#{@soup.id}[value=?]", "2"
  end

  test "the bill lists the tip that is in its total" do
    order = order_for(@diner, tip_cents: 2_000)
    sign_in_as(@diner)

    get takeaway.order_path(order)
    assert_response :success
    assert_includes response.body, I18n.t("takeaway.tip_line", amount: order.tip_display)
  end

  test "reorder is the diner's, once the order is over" do
    pending = order_for(@diner)
    delivered = order_for(@diner, status: "delivered")

    sign_in_as(@owner)
    get takeaway.order_path(delivered)
    assert_select "form[action=?]", takeaway.again_order_path(delivered), 0

    sign_in_as(@diner)
    get takeaway.order_path(pending)
    assert_select "form[action=?]", takeaway.again_order_path(pending), 0
    get takeaway.order_path(delivered)
    assert_select "form[action=?]", takeaway.again_order_path(delivered), 1
  end

  test "the courier form labels its fields, words vehicles in the locale and offers the device position" do
    driver = Takeaway::DeliveryDriver.create!(user: @diner, vehicle_type: "bicycle", available: true)
    sign_in_as(@diner)

    get takeaway.delivery_driver_path(driver)
    assert_response :success
    assert_select "label[for=delivery_driver_license_number]", text: I18n.t("takeaway.license_number")
    assert_select "label[for=delivery_driver_current_lat]", text: I18n.t("takeaway.latitude")
    assert_select "select[name='delivery_driver[vehicle_type]'] option[value=walking]",
                  text: I18n.t("takeaway.vehicle_types.walking")
    assert_select "[data-controller=current-location] button[data-action='current-location#fill']"
  end

  test "the restaurant page lists its week of opening hours, Monday first" do
    Takeaway::OpeningHour.create!(restaurant: @restaurant, weekday: 1, opens_minute: 660, closes_minute: 1320)
    Takeaway::OpeningHour.create!(restaurant: @restaurant, weekday: 5, opens_minute: 1080, closes_minute: 1560)
    host! "takeaway.brgen.no"

    get takeaway.restaurant_path(@restaurant)

    assert_select "section.store-opening-hours h2", text: I18n.t("takeaway.opening_hours_heading")
    days = css_select("section.store-opening-hours dt").map(&:text)
    assert_equal I18n.t("date.day_names").rotate(1), days
    hours = css_select("section.store-opening-hours dd").map(&:text)
    assert_equal "11:00–22:00", hours.first
    assert_equal "18:00–02:00", hours[4]
    assert_equal I18n.t("takeaway.closed_all_day"), hours.last
  end

  test "a restaurant with no recorded hours shows no hours section" do
    host! "takeaway.brgen.no"

    get takeaway.restaurant_path(@restaurant)

    assert_select "section.store-opening-hours", count: 0
  end
end
