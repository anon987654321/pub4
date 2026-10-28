# frozen_string_literal: true

require "test_helper"

# The maps home page is a full-bleed MapLibre canvas over server-rendered
# chrome. MapsLayersTest pins what gets drawn on it; this file pins the page
# itself: the DOM the Stimulus controller boots from, the no-JavaScript way
# into the list, the city centre, and the morph guard that keeps a page
# rebuild from tearing the canvas out of the running map.
class MapsHomeControllerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    host! "maps.brgen.no"
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "home answers anonymously with the section the map controller boots from" do
    get "/"

    assert_response :success
    assert_select "section[data-controller~='map']"
    assert_includes response.body, "https://tiles.openfreemap.org/styles/positron"
    assert_select "#map.map-canvas[data-map-target='canvas']"
    assert_select "input#map-search[type=search]"
    assert_select "#place-popup.map-place-popup[role=status][aria-live=polite]"
  end

  test "home carries the morph guard that keeps the canvas out of a Turbo morph" do
    get "/"

    assert_response :success
    assert_includes response.body, "data-controller=\"map map-morph-guard\""
  end

  # The city's own coordinates set the centre; a city with neither must open
  # the map on the world rather than on Bergen by accident. brgen.no is seeded
  # with its centre, so the zoom is the street level the city earns.
  test "home opens on the city centre, not on the world" do
    get "/"

    assert_response :success
    assert_includes response.body, "data-map-zoom-value=\"12\""
    assert_select "section[data-map-center-lat-value][data-map-center-lng-value]"
  end

  test "home renders a hidden heading and a no-JavaScript way into the list" do
    get "/"

    assert_response :success
    assert_select "h1.visually-hidden", text: I18n.t("maps.map")
    assert_includes response.body, I18n.t("maps.needs_js")
    assert_includes response.body, I18n.t("maps.browse_as_list")
  end
end
