# frozen_string_literal: true

require "test_helper"

class ChannelsControllerTest < ActionDispatch::IntegrationTest
  setup do
    host! "brgen.no"
    # Channel bots are city-less; keep tenant off for seating.
    ActsAsTenant.current_tenant = nil if defined?(ActsAsTenant)
  end

  test "index lists public channel rooms" do
    get channels_path
    assert_response :success
    assert_includes response.body, "channels-index"
    assert_includes response.body, "#brgen"
    assert_includes response.body, "#marketplace"
    assert_includes response.body, channel_path("dating")
  end

  test "show seeds channel and renders room" do
    assert_difference -> { Conversation.where(slug: "brgen").count }, 1 do
      get channel_path("brgen")
    end
    assert_response :success
    assert_includes response.body, "channel-room"
    assert_includes response.body, "#brgen"
    assert_includes response.body, "channel-log"

    channel = Conversation.find_by!(slug: "brgen")
    assert channel.channel?
    assert channel.messages.exists?, "welcome line from host bot"
  end

  test "show unknown slug redirects" do
    get channel_path("no-such-room")
    assert_redirected_to channels_path
  end

  test "show is idempotent" do
    get channel_path("maps")
    assert_response :success
    id = Conversation.find_by!(slug: "maps").id
    get channel_path("maps")
    assert_response :success
    assert_equal id, Conversation.find_by!(slug: "maps").id
  end
end
