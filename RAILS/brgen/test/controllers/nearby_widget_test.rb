# frozen_string_literal: true

require "test_helper"

# The floating chat widget is a turbo-frame rendered against "do we know where
# you are". At first paint the answer is always no — the browser's geolocation
# prompt has not resolved yet — so the frame rendered a "share location" dead
# end. Nothing then told it to reload, so it stayed on that dead end for the
# whole session and the chat appeared not to work at all.
#
# The reload is driven by the brgen:located event (geolocation_controller fires
# it after the first successful PATCH /location; nearby_chat_controller reloads
# the frame). These cover the two server-rendered ends of that: without
# coordinates it must offer a way to give them, and with coordinates it must
# render a room you can actually type in.
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

  test "without coordinates the widget offers to ask for them in place" do
    get nearby_widget_path

    assert_response :success
    assert_match(/nearby-chat#locate/, response.body,
                 "the CTA must ask for location in the widget, not navigate away")
    refute_match(/turbo_frame.*_top/, response.body)
  end

  # A guest is minted on every request, so Current.user is never nil here — the
  # only thing standing between a visitor and the room is coordinates.
  test "the widget is reachable without signing in" do
    get nearby_widget_path

    assert_response :success
    assert_select "turbo-frame#nearby-chat-widget-frame"
  end

  test "with coordinates the widget renders a room you can type in" do
    user = located_user
    post session_path, params: { email_address: user.email_address, password: "password123" }

    get nearby_widget_path

    assert_response :success
    assert_select "[data-nearby-chat-target=?]", "log"
    assert_select "form textarea, form input[type=text]"
  end
end
