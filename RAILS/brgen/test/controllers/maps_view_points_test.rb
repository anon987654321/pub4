# frozen_string_literal: true

require "test_helper"

# The maps page embedded its points once and never asked again, however far the
# reader panned; and the canvas's circles were the only way to reach a point.
class MapsViewPointsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @bryggen = Place.create!(city: @city, name: "Bryggen", kind: "attraction", latitude: 60.3974, longitude: 5.3244)
    @floyen = Place.create!(city: @city, name: "Fløyen", kind: "attraction", latitude: 60.3950, longitude: 5.3430)
    host! "maps.brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "the map asks for the points in a new view as JSON, through the bbox" do
    get "/", params: { sw_lat: 60.396, sw_lng: 5.320, ne_lat: 60.399, ne_lng: 5.330 }, as: :json

    assert_response :success
    titles = response.parsed_body.map { _1["title"] }
    assert_includes titles, "Bryggen"
    refute_includes titles, "Fløyen"
  end

  test "the page says where to refetch and carries the list the HUD fills" do
    get "/"

    assert_select "section[data-controller~=map][data-map-points-url-value='/']"
    assert_select ".map-hud details.map-point-list summary", /#{I18n.t("maps.point_list")}/
    assert_select ".map-hud details.map-point-list ul[data-map-target=list]"
  end
end
