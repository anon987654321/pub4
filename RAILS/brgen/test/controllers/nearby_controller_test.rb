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
    assert_equal [ a.id, b.id ].sort, ConversationParticipant.where(conversation_id: room.id).pluck(:user_id).sort
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

  test "a deletion-pending user cannot be targeted for a nearby chat" do
    lat, lng = random_base_coords
    me = User.create!(
      email_address: "nearby-me-#{SecureRandom.hex(4)}@example.com",
      password: "password12345",
      latitude: lat,
      longitude: lng
    )
    leaving = User.create!(
      email_address: "nearby-leaving-#{SecureRandom.hex(4)}@example.com",
      password: "password12345",
      latitude: lat,
      longitude: lng
    )
    leaving.update_columns(deleted_at: Time.current, deletion_scheduled_at: 7.days.from_now)

    sign_in(me)

    post nearby_path, params: { user_id: leaving.id }

    assert_response :not_found
    assert_nil Conversation.direct_between(me, leaving)
  end

  # brgen.no scopes users to Bergen; one with no city is a 404 to the endpoint.
  def bergen
    Brgen::CitySeed.sync! if City.table_exists?
    City.find_by!(domain: "brgen.no")
  end

  def located_user(tag, lat, lng)
    User.create!(email_address: "nearby-#{tag}-#{SecureRandom.hex(4)}@example.com", password: "password12345",
                 latitude: lat, longitude: lng, city: bergen)
  end

  test "a chat with someone nearby opens as a message request for them" do
    lat, lng = random_base_coords
    me = located_user("asker", lat, lng)
    other = located_user("asked", lat, lng)
    sign_in(me)

    post nearby_path, params: { user_id: other.id }

    conversation = Conversation.direct_between(me, other)
    assert conversation, "no conversation was opened"
    assert conversation.conversation_participants.find_by(user: other).request?, "the stranger got an accepted DM"
  end

  test "someone who blocked you is neither listed nor reachable nearby" do
    lat, lng = random_base_coords
    me = located_user("blocked", lat, lng)
    other = located_user("blocker", lat, lng)
    other.block!(me)
    sign_in(me)

    get nearby_path
    # The list shows anon handles, never display names; the chat button's
    # user_id is what would reach them.
    assert_select "form input[name=user_id][value=?]", other.id.to_s, count: 0

    post nearby_path, params: { user_id: other.id }
    assert_redirected_to nearby_path
    assert_nil Conversation.direct_between(me, other)
  end

  test "the list holds people in range who shared a location lately, and nobody else" do
    lat, lng = random_base_coords
    me = located_user("lister", lat, lng)
    near = located_user("near", lat + 0.01, lng)
    far = located_user("far", lat + 1.0, lng)
    stale = located_user("stale", lat, lng)

    User.where(id: [ me.id, near.id, far.id ]).update_all(location_updated_at: 1.hour.ago)
    stale.update_columns(location_updated_at: 2.days.ago)
    sign_in(me)

    get nearby_path

    listed = css_select("form input[name=user_id]").map { |input| Integer(input["value"]) }
    assert_equal [ near.id ], listed, "only the fresh, in-range person, and never the viewer"
  end

  # A distance to 0.1 km, read from three places, pins a stranger down; the list
  # says only which band someone is in, and its order says no more than that.
  test "the list shows a distance band, never a precise distance" do
    lat, lng = random_base_coords
    me = located_user("bander", lat, lng)
    # About 0.4 km and about 3 km north of the viewer.
    close = located_user("close", lat + 0.0035, lng)
    middle = located_user("middle", lat + 0.027, lng)
    User.where(id: [ me.id, close.id, middle.id ]).update_all(location_updated_at: 1.hour.ago)
    sign_in(me)

    get nearby_path(radius_km: 10)

    assert_includes response.body, I18n.t("nearby.distance_band.under_1")
    assert_includes response.body, I18n.t("nearby.distance_band.2_to_5")
    assert_no_match(/\d+[.,]\d km/, response.body)
    assert_equal "under_1", NearbyController.distance_band(0.4)
    assert_equal "1_to_2", NearbyController.distance_band(1.0)
    assert_equal "2_to_5", NearbyController.distance_band(4.99)
    assert_equal "over_5", NearbyController.distance_band(5.0)
  end

  test "visiting an unknown geo-room slug directly does not auto-create it" do
    get channel_path("nearby-999:999")
    assert_redirected_to channels_path
    refute Conversation.exists?(slug: "nearby-999:999")
  end
end
