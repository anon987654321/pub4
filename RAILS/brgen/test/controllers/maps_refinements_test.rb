# frozen_string_literal: true

require "test_helper"

# Maps and nearby: what the filter offers, what "checked in recently" means,
# who counts as nearby, and the words the map draws.
class MapsRefinementsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @user = member("mr_user", latitude: 60.39, longitude: 5.32)
    @place = Place.create!(city: @city, name: "Bryggen", kind: "attraction", latitude: 60.3974, longitude: 5.3244)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def member(handle, **attrs)
    User.strict_loading(false).create!(
      email_address: "#{handle}-#{SecureRandom.hex(3)}@brgen.no", password: "password123",
      username: "#{handle}_#{SecureRandom.hex(3)}", guest: false, city: @city, **attrs
    )
  end

  def sign_in_as(user, host: "brgen.no")
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! host
  end

  test "the kind filter offers only this city's kinds" do
    elsewhere = City.where.not(id: @city.id).first
    ActsAsTenant.with_tenant(elsewhere) do
      Place.create!(city: elsewhere, name: "Fjern", kind: "lighthouse", latitude: 59.9, longitude: 10.7)
    end
    host! "maps.brgen.no"

    get maps.places_path
    assert_response :success
    assert_select "select[name=kind] option[value=attraction]"
    assert_select "select[name=kind] option[value=lighthouse]", 0
  end

  test "a check-in from earlier in the week does not stop one today" do
    PlaceCheckIn.create!(place: @place, user: @user, checked_in_at: 2.days.ago)
    sign_in_as(@user, host: "maps.brgen.no")

    get maps.place_path(@place)
    assert_response :success
    assert_select "form.check-in-form[action=?]", maps.check_in_place_path(@place)
    assert_select "form.check-in-form[style]", 0
  end

  test "someone who shared a location weeks ago is not nearby" do
    @user.update_columns(location_updated_at: Time.current)
    stale = member("mr_stale", latitude: 60.3901, longitude: 5.3201)
    stale.update_columns(location_updated_at: 3.weeks.ago)
    fresh = member("mr_fresh", latitude: 60.3902, longitude: 5.3202)
    fresh.update_columns(location_updated_at: 10.minutes.ago)
    sign_in_as(@user)

    get nearby_path
    assert_response :success
    assert_select "form input[name=user_id][value=?]", fresh.id.to_s
    assert_select "form input[name=user_id][value=?]", stale.id.to_s, count: 0
  end

  test "the nearby widget names the room radius through the locale" do
    sign_in_as(@user)

    get nearby_widget_path, headers: { "Turbo-Frame" => "nearby-chat-widget-frame" }
    assert_response :success
    assert_includes response.body, I18n.t("nearby.room_radius", km: Conversation::GEO_ROOM_RADIUS_KM.to_i)
  end

  test "the map carries its popup and list words from the locale" do
    host! "maps.brgen.no"

    get "/"
    assert_response :success
    assert_select "[data-controller~=map][data-map-empty-label-value=?]", I18n.t("maps.no_points")
    assert_select "[data-controller~=map][data-map-open-label-value=?]", I18n.t("maps.popup_open")
  end
end
