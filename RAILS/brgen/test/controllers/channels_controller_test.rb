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

  # Every other test in this file runs tenant-less, so the channel is created
  # with city_id = nil and `belongs_to :city` answers nil without a query --
  # which is exactly the one case strict_loading cannot fire on. In production
  # every channel is city-scoped, so the room 500'd on every open.
  class CityScopedChannelTest < ActionDispatch::IntegrationTest
    setup do
      Brgen::CitySeed.sync! if City.table_exists?
      @city = City.find_by!(domain: "brgen.no")
      host! "brgen.no"
    end

    teardown { ActsAsTenant.current_tenant = nil }

    test "a city-scoped room renders its title and log" do
      get channel_path("brgen")

      assert_response :success
      assert_includes response.body, "channel-room"
      assert_includes response.body, "#brgen · #{@city.name}"
      assert_includes response.body, "channel-log"

      channel = Conversation.find_by!(slug: "brgen", city_id: @city.id)
      assert channel.messages.exists?, "welcome line from host bot"
    end

    test "a city-scoped room renders messages from a soft guest" do
      get channel_path("brgen")
      assert_response :success
      conversation = Conversation.find_by!(slug: "brgen", city_id: @city.id)

      post conversation_messages_path(conversation),
           params: { message: { content: "hei fra byen", message_type: "text" } }

      get channel_path("brgen")
      assert_response :success
      assert_includes response.body, "hei fra byen"
    end
  end
end
