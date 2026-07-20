# frozen_string_literal: true

require "test_helper"

class RecentFeaturesIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @city = bergen_city
    ActsAsTenant.current_tenant = @city
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def bergen_city
    city = City.find_or_initialize_by(domain: "brgen.no")
    city.name ||= "Bergen"
    city.slug ||= "bergen-test"
    city.country_code ||= "NO"
    city.locale ||= "nb"
    city.currency = "NOK"
    city.save!
    city
  end

  def sign_in_on(host, user)
    host! host
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  def sign_in_with_session_cookie!(user)
    session = user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
    secret = Rails.application.key_generator.generate_key("signed cookie")
    verifier = ActiveSupport::MessageVerifier.new(
      secret,
      digest: "SHA1",
      serializer: ActiveSupport::MessageEncryptor::NullSerializer
    )
    cookies[:session_id] = verifier.generate(session.id.to_s)
  end

  test "user profile is public and follow requires auth" do
    host! "brgen.no"
    subject = User.create!(
      email_address: "profile@brgen.no",
      password: "password123",
      password_confirmation: "password123",
      username: "profile_user"
    )

    get user_path(subject)
    assert_response :success
    assert_includes response.body, subject.display_name

    post follow_user_path(subject)
    assert_redirected_to new_session_path
  end

  test "authenticated follow toggles on profile" do
    host! "brgen.no"
    subject = User.create!(
      email_address: "followed@brgen.no",
      password: "password123",
      password_confirmation: "password123",
      username: "followed_user"
    )
    follower = User.create!(
      email_address: "follower@brgen.no",
      password: "password123",
      password_confirmation: "password123",
      username: "follower_user"
    )
    sign_in_on("brgen.no", follower)

    assert_difference -> { Follow.count }, 1 do
      post follow_user_path(subject)
    end
    assert follower.following?(subject)
  end

  test "maps check-in requires authentication" do
    host! "maps.brgen.no"
    place = Place.create!(
      city: @city,
      name: "Test Place",
      kind: "cafe",
      latitude: 60.39,
      longitude: 5.32
    )

    post check_in_maps_place_path(place), params: { note: "hello" }
    assert_redirected_to new_session_path
  end

  test "maps check-in persists for signed-in user" do
    host! "maps.brgen.no"
    place = Place.create!(
      city: @city,
      name: "Check-in Spot",
      kind: "park",
      latitude: 60.39,
      longitude: 5.32
    )
    user = User.create!(
      email_address: "maps@brgen.no",
      password: "password123",
      password_confirmation: "password123",
      username: "maps_user"
    )
    sign_in_with_session_cookie!(user)

    post check_in_maps_place_path(place), params: { note: "here" }
    assert_redirected_to maps_place_path(place)
    assert PlaceCheckIn.exists?(user: user, place: place), "expected check-in to persist for signed-in user"
  end

  test "listening party can be started on a set" do
    host! "playlist.brgen.no"
    user = User.create!(
      email_address: "dj@brgen.no",
      password: "password123",
      password_confirmation: "password123",
      username: "dj_user"
    )
    set = Playlist::Set.create!(name: "Friday set", user: user)
    track = Playlist::Track.create!(title: "Track 1", artist: "Artist")
    set.add_track!(track, user: user)
    sign_in_with_session_cookie!(user)

    assert_difference -> { Playlist::ListeningParty.count }, 1 do
      post playlist_set_listening_party_path(set)
    end

    party = Playlist::ListeningParty.includes(:host).find_by!(playlist_set_id: set.id)
    assert party.active?
    assert_equal user, party.host
    assert party.join_code.present?
  end
end
