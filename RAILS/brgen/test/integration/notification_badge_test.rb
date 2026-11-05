# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

# Every page carries the reader's unread notification count beside Varsler,
# subscribed to the stream that redraws it; read_all redraws it to nothing.
class NotificationBadgeTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @reader = User.strict_loading(false).create!(email_address: "badge-page@brgen.no", password: "password123",
                                                 username: "varslet", guest: false, city: @city)
    host! "brgen.no"
    post session_path, params: { email_address: @reader.email_address, password: "password123" }
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "the menu shows the unread count and reads its stream" do
    2.times { Notification.create!(user: @reader, kind: "follow") }
    get root_path

    assert_response :success
    assert_select %(a[href="#{notifications_path}"] #notifications-unread-badge sup), text: "2"
    names = css_select("turbo-cable-stream-source").map { |source| source["signed-stream-name"] }
    assert_includes names, Turbo::StreamsChannel.signed_stream_name(Notification.unread_badge_stream(@reader))
  end

  test "no number when nothing is unread" do
    get root_path

    assert_select "#notifications-unread-badge", 1
    assert_select "#notifications-unread-badge sup", 0
  end

  test "reading all redraws the badge empty" do
    Notification.create!(user: @reader, kind: "follow")

    streams = capture_turbo_stream_broadcasts(Notification.unread_badge_stream(@reader)) do
      patch read_all_notifications_path, as: :turbo_stream
    end

    assert(streams.any? { |stream| stream["target"] == "notifications-unread-badge" && stream.at_css("sup").nil? })
    assert_equal 0, Notification.where(user: @reader).unread.count
  end

  test "the tab bar shows unread messages on Messages and unread notifications on More" do
    Notification.create!(user: @reader, kind: "follow")
    friend = User.strict_loading(false).create!(email_address: "badge-friend@brgen.no", password: "password123",
                                                username: "badgevenn", guest: false, city: @city)
    conversation = Conversation.find_or_create_direct(@reader, friend)
    conversation.messages.create!(sender: friend, content: "Hei", message_type: "text")
    get root_path

    assert_select %(#app-tab-bar a[href="#{conversations_path}"][aria-describedby="messenger_unread_badge_tab"]) do
      badge = "#messenger_unread_badge_tab[data-controller=unread-title][data-unread-title-count-value=1]"
      assert_select "#{badge} sup", text: "1"
    end
    assert_select %(#app-tab-bar button[aria-describedby="notifications-unread-badge-tab"]) do
      assert_select "#notifications-unread-badge-tab sup", text: "1"
    end
    assert_select "#messenger_unread_badge", 1
    assert_select "#notifications-unread-badge", 1
  end
end
