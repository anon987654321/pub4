# frozen_string_literal: true

require "test_helper"

# MapsLayersTest covers what the map draws; this file covers the surfaces the
# map links to: the places list and its JSON twin, the place page a pin opens,
# and the check-in contract those pages carry. All of it answers on the maps
# subdomain, over the host's Place and PlaceCheckIn tables.
class MapsPlacesControllerTest < ActionDispatch::IntegrationTest
  STREAM = { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }.freeze

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @user = User.strict_loading(false).create!(
      email_address: "mp_user@brgen.no", password: "password123", username: "mp_user", guest: false
    )
    host! "maps.brgen.no"
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "the places list renders its cards inside the live search frame" do
    place = Place.create!(city: @city, name: "Bryggen", kind: "attraction", latitude: 60.3974, longitude: 5.3244)

    get "/places"

    assert_response :success
    assert_select "h1", text: I18n.t("pages.places")
    assert_select "form[action=?]", "/places"
    assert_select "select[name=kind][aria-label=?]", I18n.t("maps.filter_by_kind")
    assert_select "select[name=kind] option", text: I18n.t("maps.all_types")
    assert_select "turbo-frame#maps-places"
    assert_select "article.place-card h2 a[href=?]", "/places/#{place.to_param}", text: "Bryggen"
  end

  test "an unmatched search answers with the empty state and a way to clear it" do
    get "/places", params: { q: "no-such-place-anywhere" }

    assert_response :success
    assert_select ".empty-state-title", text: I18n.t("empty.no_places")
    assert_select "a[href=?]", "/places", text: I18n.t("empty.clear_search")
  end

  test "the JSON twin answers with coordinates for the map to pin" do
    Place.create!(city: @city, name: "Bryggen", kind: "attraction", latitude: 60.3974, longitude: 5.3244)
    cafe = Place.create!(city: @city, name: "Kafeteket", kind: "cafe", latitude: 60.3910, longitude: 5.3310)

    get "/places.json"

    assert_response :success
    rows = JSON.parse(response.body)
    assert_equal 2, rows.size
    row = rows.find { |r| r["name"] == "Kafeteket" }
    assert_equal %w[city id kind lat lng name neighborhood], row.keys.sort
    assert_equal cafe.latitude.to_f, row["lat"].to_f
    assert_equal cafe.longitude.to_f, row["lng"].to_f
    assert_equal @city.name, row["city"]
  end

  test "the JSON twin honours the kind filter the map sends" do
    Place.create!(city: @city, name: "Bryggen", kind: "attraction", latitude: 60.3974, longitude: 5.3244)
    Place.create!(city: @city, name: "Kafeteket", kind: "cafe", latitude: 60.3910, longitude: 5.3310)

    get "/places.json", params: { kind: "cafe" }

    assert_response :success
    rows = JSON.parse(response.body)
    assert_equal [ "Kafeteket" ], rows.map { |r| r["name"] }
  end

  # The scope rule every Maps read runs under: a missing city resolves to an
  # empty scope, never the whole table. The maps_layers cross-city tests pin
  # show and check_in on it; the JSON twin that feeds the map pins it here.
  test "the JSON twin answers another city with an empty scope" do
    Place.create!(city: @city, name: "Bryggen", kind: "attraction", latitude: 60.3974, longitude: 5.3244)

    host! "maps.oshlo.no"
    get "/places.json"

    assert_response :success
    assert_empty JSON.parse(response.body)
  end

  test "a live search streams the matched cards into the results slot" do
    Place.create!(city: @city, name: "Bryggen", kind: "attraction", latitude: 60.3974, longitude: 5.3244)

    get "/places", params: { q: "bryggen" }, headers: STREAM

    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, '<turbo-stream action="update" target="live_search_results">'
    assert_includes response.body, "Bryggen"
  end

  test "a place page shows its address, an OSM escape hatch and its neighbours" do
    place = Place.create!(city: @city, name: "Bryggen", kind: "attraction", address: "Strandgaten 9",
                          latitude: 60.3974, longitude: 5.3244)
    Place.create!(city: @city, name: "Nordnes", kind: "attraction", latitude: 60.3995, longitude: 5.3150)

    get "/places/#{place.id}"

    assert_response :success
    assert_select "h1", text: "Bryggen"
    assert_select "dd", text: "Strandgaten 9"
    assert_select "dt", text: I18n.t("maps.coordinates")
    assert_includes response.body, "openstreetmap.org/?mlat="
    assert_select "aside.also-nearby li a", text: "Nordnes"
  end

  # PlacesController#check_in asks for require_user_session -- the check that
  # means "any identity, guests included". An anonymous visitor arrives with a
  # soft guest from resume_session, so the form is on the page and the write
  # lands under that guest, with no signup step anywhere in the middle.
  test "a guest sees the check-in form and the write lands under the soft guest" do
    place = Place.create!(city: @city, name: "Bryggen", kind: "attraction", latitude: 60.3974, longitude: 5.3244)

    get "/places/#{place.id}"

    assert_response :success
    assert_select "form[action=?]", "/places/#{place.id}/check_in" do
      assert_select "input[name=note]"
    end
    assert_select "input[type=submit][value=?]", I18n.t("maps.check_in")

    assert_difference -> { PlaceCheckIn.count }, 1 do
      post "/places/#{place.id}/check_in", params: { note: "her" }
    end
    assert_redirected_to "/places/#{place.id}"
    assert_equal I18n.t("flash.checked_in_at", place: place.name), flash[:notice]

    check_in = PlaceCheckIn.order(:id).last
    assert_equal place, check_in.place
    assert check_in.user.guest?, "the soft guest is a real identity for check-ins"
  end

  test "a place page lists the check-ins visitors left behind" do
    place = Place.create!(city: @city, name: "Bryggen", kind: "attraction", latitude: 60.3974, longitude: 5.3244)
    PlaceCheckIn.create!(place: place, user: @user, note: "Solbaer i baggen", checked_in_at: Time.current)

    get "/places/#{place.id}"

    assert_response :success
    assert_select "li", text: /Solbaer i baggen/
    assert_select "li time[datetime]"
  end

  test "a note that breaks the model bounces back with the failure flash" do
    place = Place.create!(city: @city, name: "Bryggen", kind: "attraction", latitude: 60.3974, longitude: 5.3244)

    assert_no_difference -> { PlaceCheckIn.count } do
      post "/places/#{place.id}/check_in", params: { note: "x" * 281 }
    end
    assert_redirected_to "/places/#{place.id}"
    assert_equal I18n.t("flash.check_in_failed"), flash[:alert]
  end
end
