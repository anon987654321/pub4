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

  test "a failed update says why" do
    host! "brgen.no"
    post session_path, params: { email_address: @courier.email_address, password: "password123" }
    host! "takeaway.brgen.no"

    patch takeaway.delivery_driver_path(@driver), params: { delivery_driver: { vehicle_type: "hovercraft" } }

    assert_response :unprocessable_entity
    assert_select "section.errors[role=alert]"
  end
end
