# frozen_string_literal: true

require "test_helper"

# Ambient chat widget: without GPS → #brgen lobby inline; with GPS → geo room.
class NearbyWidgetTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def located_user
    User.strict_loading(false).create!(
      email_address: "widget-#{SecureRandom.hex(4)}@brgen.no",
      password: "password123", city: @city,
      latitude: 60.39, longitude: 5.32,
    )
  end

  test "without coordinates the widget opens #brgen lobby with a composer" do
    get nearby_widget_path

    assert_response :success
    assert_includes response.body, "#brgen"
    assert_select "form textarea, form input[type=text]"
    assert_match(/nearby-chat#locate/, response.body)
  end

  test "the widget is reachable without signing in" do
    get nearby_widget_path

    assert_response :success
    assert_select "turbo-frame#nearby-chat-widget-frame"
    refute_match(/Sign in to message|Sign in to join/i, response.body)
  end

  test "with coordinates the widget renders the nearby room" do
    user = located_user
    post session_path, params: { email_address: user.email_address, password: "password123" }

    get nearby_widget_path

    assert_response :success
    assert_includes response.body, "#nearby"
    assert_select "[data-nearby-chat-target=?]", "log"
    assert_select "form textarea, form input[type=text]"
  end
end
