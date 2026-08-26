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

  # The composer that comes back after a send has to be usable for the *next*
  # send. create_widget.turbo_stream.erb passed the persisted @message straight
  # into form_with, so the reset form carried method="patch" and the text that
  # had just been sent -- and routes.rb declares
  # `resources :messages, only: [ :create ]`, so there is no PATCH route for it
  # to post to. Every assertion in the test above passed while the second send
  # was impossible, which is why this one checks the form's shape.
  test "the composer returned after a send is an empty create form" do
    get_widget
    conversation = Conversation.find_by(slug: "brgen")

    post conversation_messages_path(conversation),
         params: { message: { content: "første melding", message_type: "text" }, origin: "widget" },
         as: :turbo_stream

    assert_response :success
    assert_select "form#nearby_widget_message" do
      assert_select "input[name=_method]", 0, "reset composer must not be a PATCH form"
      assert_select "textarea" do |fields|
        assert_equal "", fields.first.text.strip, "reset composer must not keep the sent text"
      end
    end
    assert_includes response.body, conversation_messages_path(conversation)
  end

  test "a soft guest can send twice in a row" do
    get_widget
    conversation = Conversation.find_by(slug: "brgen")

    assert_difference -> { Message.count }, +2 do
      [ "en", "to" ].each do |body|
        post conversation_messages_path(conversation),
             params: { message: { content: body, message_type: "text" }, origin: "widget" },
             as: :turbo_stream
        assert_response :success
      end
    end

    assert_equal [ "en", "to" ], conversation.messages.order(:created_at).last(2).map(&:content)
  end

  test "a validation miss keeps the rejected text so it is not lost" do
    get_widget
    conversation = Conversation.find_by(slug: "brgen")

    assert_no_difference -> { Message.count } do
      post conversation_messages_path(conversation),
           params: { message: { content: "", message_type: "text" }, origin: "widget" },
           as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_select "form#nearby_widget_message"
    assert_select "input[name=_method]", 0
  end

  test "the widget renders without the application layout" do
    get_widget

    assert_response :success
    # A turbo-frame body, not a page: rendered inside the layout this answered
    # 64,640 bytes -- and included a second copy of the chat widget that had
    # requested it -- for the frame Turbo actually keeps.
    refute_match(/<!DOCTYPE html>/i, response.body)
    refute_match(/nearby-chat-widget-tab/, response.body)
    assert_select "turbo-frame#nearby-chat-widget-frame"
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

  # The tab used to render t("chat.title") = "chat" and let
  # nearby_chat_controller#syncLabelsFromFrame rewrite it to the room name once
  # the turbo-frame arrived. That is a visible relabel a beat after the page
  # settles, and it made layout_snapshot report
  # `.nearby-chat-widget-tab: w 92 -> 102` on and off for many runs in both
  # directions -- re-baselining never converged, because it re-recorded
  # whichever side of the race that run caught.
  #
  # Both sides now read Shared::UiHelper#ambient_chat_room_label, so there is one
  # source and nothing to swap. These two cases are what keeps them equal: assert
  # the tab renders the room name, not the generic word.
  test "the chat tab renders the room name server-side, so nothing relabels after load" do
    get root_path

    assert_response :success
    assert_select "[data-nearby-chat-target=?]", "tabLabel" do |labels|
      assert_equal 1, labels.size
      assert_equal "brgen", labels.first.text.strip,
                   "the tab must ship the room it will land in, not a placeholder the JS replaces"
    end
  end

  test "the tab label and the frame's room line come from the same source" do
    user = located_user
    post session_path, params: { email_address: user.email_address, password: "password123" }

    get root_path
    assert_response :success
    tab_label = css_select("[data-nearby-chat-target=tabLabel]").first.text.strip

    get_widget
    assert_response :success
    frame_room = css_select("[data-nearby-chat-target=mode] strong").first.text.strip

    assert_equal "nearby", tab_label
    assert_equal "##{tab_label}", frame_room,
                 "syncLabelsFromFrame strips the leading # and assigns; if these disagree the tab relabels on load"
  end
end
