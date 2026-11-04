# frozen_string_literal: true

require "test_helper"

class TakeawayDeliveryDriverShowTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @courier = User.strict_loading(false).create!(
      email_address: "courier_show@brgen.no", password: "password123",
      username: "courier_show", guest: false, city: @city
    )
    @driver = Takeaway::DeliveryDriver.create!(user: @courier, vehicle_type: "bicycle", available: true)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  # show names the courier and compares Current.user to the driver's user, both
  # association reads off a record found by id — which strict loading refuses.
  test "the driver page renders for its owner" do
    host! "brgen.no"
    post session_path, params: { email_address: @courier.email_address, password: "password123" }
    host! "takeaway.brgen.no"

    get takeaway.delivery_driver_path(@driver)

    assert_response :success
    assert_select "form[action='#{takeaway.delivery_driver_path(@driver)}']"
  end

  def job_for(driver)
    owner = User.strict_loading(false).create!(email_address: "kitchen_#{SecureRandom.hex(3)}@brgen.no",
                                               password: "password123", guest: false, city: @city)
    kitchen = Takeaway::Restaurant.create!(user: owner, name: "Budkjøkken", address: "Marken 41",
                                           cuisine_type: "Norwegian", city: @city, active: true, min_order_cents: 0)
    soup = Takeaway::MenuItem.create!(restaurant: kitchen, name: "Suppe", price_cents: 9_900, available: true)
    order = kitchen.orders.build(user: owner, delivery_address: "Torget 8")
    order.order_items.build(menu_item: soup, quantity: 1, unit_price_cents: soup.price_cents)
    order.save!
    order.update_columns(status: "out_for_delivery", delivery_driver_id: driver.id)
    order
  end

  def sign_in_courier(user = @courier)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "takeaway.brgen.no"
  end

  test "the courier sees the job dispatch gave them and marks it delivered" do
    order = job_for(@driver)
    sign_in_courier

    get takeaway.delivery_driver_path(@driver)
    assert_select "section li", text: /Torget 8/ do
      assert_select "form[action=?] input[name=status][value=delivered]", takeaway.order_path(order)
    end

    patch takeaway.order_path(order, status: "delivered")
    assert_redirected_to takeaway.delivery_driver_path(@driver)
    assert_equal "delivered", order.reload.status
  end

  test "another courier can neither see the job nor mark it" do
    order = job_for(@driver)
    other = User.strict_loading(false).create!(email_address: "courier_other_#{SecureRandom.hex(3)}@brgen.no",
                                               password: "password123", guest: false, city: @city)
    Takeaway::DeliveryDriver.create!(user: other, vehicle_type: "car", available: true)
    sign_in_courier(other)

    get takeaway.delivery_driver_path(@driver)
    assert_select "section li", 0
    patch takeaway.order_path(order, status: "delivered")
    assert_equal "out_for_delivery", order.reload.status
  end

  test "a failed update says why" do
    host! "brgen.no"
    post session_path, params: { email_address: @courier.email_address, password: "password123" }
    host! "takeaway.brgen.no"

    patch takeaway.delivery_driver_path(@driver), params: { delivery_driver: { vehicle_type: "hovercraft" } }

    assert_response :unprocessable_entity
    assert_select "section.errors[role=alert]"
  end
end
