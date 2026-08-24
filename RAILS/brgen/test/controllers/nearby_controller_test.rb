# frozen_string_literal: true

require "test_helper"

class NearbyControllerTest < ActionDispatch::IntegrationTest
  setup do
    host! "brgen.no"
  end

  def sign_in(user)
    post session_url, params: { email_address: user.email_address, password: "password12345" }
  end

  # Tests here aren't guaranteed transactional isolation from each other (this
  # codebase's other controller tests randomize emails for the same reason --
  # see posts_controller_test.rb), so every test picks its own random base
  # coordinate rather than sharing a fixed one, to guarantee its geo room's
  # slug can't collide with another test's.
  def random_base_coords
    [ 40 + rand(40.0), -20 + rand(60.0) ]
  end

  def geo_room_slug(lat, lng)
    "nearby-#{Shared::GeoLocatable.cell_id(lat: lat, lng: lng, km: Conversation::GEO_ROOM_RADIUS_KM)}"
  end

  test "room without a stored location redirects with an alert" do
    user = User.create!(email_address: "nearby-nolocation-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    sign_in(user)

    get nearby_room_path
    assert_redirected_to nearby_path
    assert_equal I18n.t("flash.location_required_for_nearby"), flash[:alert]
  end

  test "room creates and joins an anonymous geo-scoped group room" do
    lat, lng = random_base_coords
    user = User.create!(email_address: "nearby-room-#{SecureRandom.hex(4)}@example.com", password: "password12345",
                         latitude: lat, longitude: lng)
    sign_in(user)

    assert_difference -> { Conversation.count }, 1 do
      get nearby_room_path
    end

    conversation = Conversation.find_by!(slug: geo_room_slug(lat, lng))
    assert conversation.channel?
    assert_nil conversation.city_id
    assert conversation.participants.include?(user)
    assert_redirected_to channel_path(conversation.slug)
  end

  test "two users within the radius land in the same shared room" do
    # Same coordinates for both -- proves the grouping (same cell -> same
    # slug -> same room), without risking a random base that happens to sit
    # near a cell boundary and pushes a small offset into the next cell over.
    lat, lng = random_base_coords
    a = User.create!(email_address: "nearby-a-#{SecureRandom.hex(4)}@example.com", password: "password12345",
                      latitude: lat, longitude: lng)
    b = User.create!(email_address: "nearby-b-#{SecureRandom.hex(4)}@example.com", password: "password12345",
                      latitude: lat, longitude: lng)

    sign_in(a)
    get nearby_room_path

    sign_in(b)
    get nearby_room_path

    room = Conversation.find_by!(slug: geo_room_slug(lat, lng))
    assert_equal [ a.id, b.id ].sort, room.participants.pluck(:id).sort
  end

  test "messages in a geo room render under the anonymous handle, not the real display name" do
    lat, lng = random_base_coords
    user = User.create!(email_address: "nearby-anon-#{SecureRandom.hex(4)}@example.com", password: "password12345",
                         username: "realname", latitude: lat, longitude: lng)
    sign_in(user)
    get nearby_room_path
    conversation = Conversation.find_by!(slug: geo_room_slug(lat, lng))

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
