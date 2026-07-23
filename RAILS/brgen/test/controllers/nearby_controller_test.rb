# frozen_string_literal: true

require "test_helper"

class NearbyControllerTest < ActionDispatch::IntegrationTest
  setup do
    host! "brgen.no"
  end

  def sign_in(user)
    post session_url, params: { email_address: user.email_address, password: "password12345" }
  end

  test "room without a stored location redirects with an alert" do
    user = User.create!(email_address: "nearby-nolocation-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    sign_in(user)

    get nearby_room_path
    assert_redirected_to nearby_path
    assert_equal "Enable location to join the nearby chat room.", flash[:alert]
  end

  test "room creates and joins an anonymous geo-scoped group room" do
    user = User.create!(email_address: "nearby-room-#{SecureRandom.hex(4)}@example.com", password: "password12345",
                         latitude: 60.39299, longitude: 5.32415)
    sign_in(user)

    assert_difference -> { Conversation.count }, 1 do
      get nearby_room_path
    end

    conversation = Conversation.last
    assert conversation.channel?
    assert conversation.slug.start_with?("nearby-")
    assert_nil conversation.city_id
    assert conversation.participants.include?(user)
    assert_redirected_to channel_path(conversation.slug)
  end

  test "two users within the radius land in the same shared room" do
    a = User.create!(email_address: "nearby-a-#{SecureRandom.hex(4)}@example.com", password: "password12345",
                      latitude: 60.39299, longitude: 5.32415)
    b = User.create!(email_address: "nearby-b-#{SecureRandom.hex(4)}@example.com", password: "password12345",
                      latitude: 60.41, longitude: 5.35) # ~2km away

    sign_in(a)
    get nearby_room_path
    room_a = Conversation.find_by!(slug: Conversation.last.slug)

    sign_in(b)
    get nearby_room_path
    room_b = Conversation.last

    assert_equal room_a.id, room_b.id
    assert_equal [a.id, b.id].sort, room_b.participants.pluck(:id).sort
  end

  test "messages in a geo room render under the anonymous handle, not the real display name" do
    user = User.create!(email_address: "nearby-anon-#{SecureRandom.hex(4)}@example.com", password: "password12345",
                         username: "realname", latitude: 60.39299, longitude: 5.32415)
    sign_in(user)
    get nearby_room_path
    conversation = Conversation.last

    post conversation_messages_url(conversation), params: { message: { content: "hello nearby" } }
    get channel_path(conversation.slug)

    assert_includes response.body, user.anon_handle
    refute_includes response.body, "realname"
  end

  test "visiting an unknown geo-room slug directly does not auto-create it" do
    get channel_path("nearby-999:999")
    assert_redirected_to channels_path
    refute Conversation.exists?(slug: "nearby-999:999")
  end
end
