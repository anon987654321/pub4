# frozen_string_literal: true

require "test_helper"

# Ambient chat widget: without GPS → #brgen lobby inline; with GPS → geo room.
# Soft guests chat without signup (Craigslist-style).
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

  def get_widget
    # Frame request — same path the dock uses; avoids the layout's lazy
    # "Loading…" placeholder matching lobby assertions.
    get nearby_widget_path, headers: { "Turbo-Frame" => "nearby-chat-widget-frame" }
  end

  test "without coordinates the widget opens #brgen lobby with a composer" do
    get_widget

    assert_response :success
    assert_includes response.body, "#brgen"
    assert_select "form#nearby_widget_message"
    assert_select "form textarea, form input[type=text]"
    assert_match(/nearby-chat#locate/, response.body)
    assert_select "input[name=origin][value=widget]"
    refute_match(/>\s*(Loading the room|Laster rommet)…?\s*</, response.body)
  end

  test "the widget is reachable without signing in" do
    get_widget

    assert_response :success
    assert_select "turbo-frame#nearby-chat-widget-frame"
    refute_match(/Sign in to message|Sign in to join/i, response.body)
  end

  test "soft guest can send a message through the widget" do
    get_widget
    assert_response :success

    conversation = Conversation.find_by(slug: "brgen")
    assert conversation, "lobby channel should exist after widget open"

    assert_difference -> { Message.count }, +1 do
      post conversation_messages_path(conversation),
           params: {
             message: { content: "hei fra hjørnet", message_type: "text" },
             origin: "widget"
           },
           as: :turbo_stream
    end
    assert_response :success
    assert_match(/nearby_widget_message|nearby-chat-widget-composer/, response.body)
  end

  test "with coordinates the widget renders the nearby room" do
    user = located_user
    post session_path, params: { email_address: user.email_address, password: "password123" }

    get_widget

    assert_response :success
    assert_includes response.body, "#nearby"
    assert_select "[data-nearby-chat-target=?]", "log"
    assert_select "form textarea, form input[type=text]"
  end
end
