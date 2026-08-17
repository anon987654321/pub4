# frozen_string_literal: true

require "test_helper"

# Three "still open" lines were one surface: the courier position, event pins
# and the story Snap-Map all stored coordinates that nothing drew.
#
# And the layer that *was* drawn was mislabelled — the Stimulus controller reads
# point.title/subtitle/url/type and the server sent name/kind/city, so every
# marker on the live map said "Map point" with an Open link pointing at "#".
class MapsLayersTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @user = User.strict_loading(false).create!(
      email_address: "ml_user@brgen.no", password: "password123", username: "ml_user", guest: false
    )
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def in_maps = host!("maps.brgen.no")

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  def points
    doc = response.body[/data-map-points-value="([^"]*)"/, 1].to_s
    JSON.parse(CGI.unescapeHTML(doc))
  end

  test "a place is drawn with its own name, not the string Map point" do
    Place.create!(city: @city, name: "Bryggen", kind: "attraction", latitude: 60.3974, longitude: 5.3244)
    in_maps

    get "/"
    assert_response :success
    place = points.find { |p| p["type"] == "place" }
    assert_equal "Bryggen", place["title"]
    assert_equal "/places/#{Place.last.to_param}", place["url"]
    refute_equal "#", place["url"]
  end

  test "an upcoming event with coordinates is pinned" do
    event = Event.create!(
      user: @user, title: "Konsert pa Landmark", starts_at: 2.days.from_now,
      latitude: 60.3925, longitude: 5.3242
    )
    in_maps

    get "/"
    pin = points.find { |p| p["type"] == "event" }
    assert_equal event.title, pin["title"]
    assert_equal "http://brgen.no/events/#{event.to_param}", pin["url"]
  end

  test "an event beyond the horizon is not clutter on the map" do
    Event.create!(
      user: @user, title: "Neste maned", starts_at: 30.days.from_now,
      latitude: 60.39, longitude: 5.32
    )
    in_maps

    get "/"
    assert_nil points.find { |p| p["type"] == "event" }
  end

  test "a live story is pinned and an expired one is not" do
    fresh = Story.new(user: @user, caption: "Regn", latitude: 60.39, longitude: 5.32)
    fresh.media.attach(ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("x"), filename: "s.jpg", content_type: "image/jpeg", identify: false
    ))
    fresh.save!

    stale = Story.new(user: @user, caption: "Gammelt", latitude: 60.39, longitude: 5.32)
    stale.media.attach(ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("x"), filename: "s2.jpg", content_type: "image/jpeg", identify: false
    ))
    stale.save!
    stale.update_columns(expires_at: 1.hour.ago)

    in_maps
    get "/"
    story_pins = points.select { |p| p["type"] == "story" }
    assert_equal 1, story_pins.size
    assert_equal "http://brgen.no/stories/#{fresh.id}", story_pins.first["url"]
  end

  # A live position is the courier's, not the city's. Publishing every rider's
  # location would be tracking people who never agreed to it, and the person
  # waiting for the food is the only one who needs it.
  test "a courier is drawn for the customer waiting on that order, and for nobody else" do
    owner = User.strict_loading(false).create!(
      email_address: "ml_owner@brgen.no", password: "password123", guest: false
    )
    rider_user = User.strict_loading(false).create!(
      email_address: "ml_rider@brgen.no", password: "password123", guest: false
    )
    restaurant = Takeaway::Restaurant.create!(
      user: owner, name: "Kjokken", address: "Marken 4", cuisine_type: "Norwegian",
      city: @city, active: true, latitude: 60.39, longitude: 5.32
    )
    driver = Takeaway::DeliveryDriver.create!(
      user: rider_user, vehicle_type: "bicycle", available: true,
      current_lat: 60.3930, current_lng: 5.3250
    )
    order = place_takeaway_order!(user: @user, restaurant: restaurant, status: "out_for_delivery", delivery_driver: driver)

    # A stranger sees no courier at all.
    stranger = User.strict_loading(false).create!(
      email_address: "ml_stranger@brgen.no", password: "password123", guest: false
    )
    sign_in_as(stranger)
    in_maps
    get "/"
    assert_nil points.find { |p| p["type"] == "courier" },
               "a rider's live position must not be published to the whole city"

    sign_in_as(@user)
    in_maps
    get "/"
    courier = points.find { |p| p["type"] == "courier" }
    assert_not_nil courier, "the person waiting for the food is who this is for"
    # The pin has to carry the host, not just the path: an order lives on the
    # takeaway subdomain and the map is drawn on the apex.
    assert_equal "http://takeaway.brgen.no/orders/#{order.id}", courier["url"]
  end

  test "a delivered order stops drawing its courier" do
    owner = User.strict_loading(false).create!(
      email_address: "ml_owner2@brgen.no", password: "password123", guest: false
    )
    rider_user = User.strict_loading(false).create!(
      email_address: "ml_rider2@brgen.no", password: "password123", guest: false
    )
    restaurant = Takeaway::Restaurant.create!(
      user: owner, name: "Kjokken2", address: "Marken 6", cuisine_type: "Norwegian",
      city: @city, active: true, latitude: 60.39, longitude: 5.32
    )
    driver = Takeaway::DeliveryDriver.create!(
      user: rider_user, available: true, current_lat: 60.393, current_lng: 5.325
    )
    place_takeaway_order!(user: @user, restaurant: restaurant, delivery_address: "Torget 2", status: "delivered", delivery_driver: driver)

    sign_in_as(@user)
    in_maps
    get "/"
    assert_nil points.find { |p| p["type"] == "courier" }
  end
end
