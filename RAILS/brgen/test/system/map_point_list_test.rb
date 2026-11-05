# frozen_string_literal: true

require "application_system_test_case"

# The points on the maps page as links a keyboard reaches, kept in step with the
# search and with a refetch for a new view.
class MapPointListTest < ApplicationSystemTestCase
  include CityHostSystemTest

  setup do
    Brgen::CitySeed.sync! if City.table_exists? && !City.exists?(domain: "brgen.no")
    city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.with_tenant(city) do
      Place.create!(city:, name: "Bryggen", kind: "attraction", latitude: 60.3974, longitude: 5.3244)
      Place.create!(city:, name: "Fløyen", kind: "attraction", latitude: 60.3950, longitude: 5.3430)
    end
  end

  def list_titles = all(".map-point-list li", visible: :all).map { _1.text(:all).strip }

  # What MapLibre's getBounds() hands the controller on moveend, as a value.
  Bounds = Data.define(:south, :west, :north, :east)

  def refetch(bounds)
    execute_script("window.mapRefetch(arguments[0])", bounds.to_h.transform_keys(&:to_s))
  end

  # A page hook for the test, so the JavaScript stays one line here.
  def expose_refetch
    execute_script("window.mapRefetch = (b) => window.Stimulus.getControllerForElementAndIdentifier(" \
                   "document.querySelector('[data-controller~=map]'), 'map')" \
                   ".viewPoints.refetch({ getSouth: () => b.south, getWest: () => b.west, getNorth: () => b.north, getEast: () => b.east })")
  end

  test "the HUD lists the points as links, filtered by the search and refetched for a new view" do
    visit_city("maps", "/")
    decline_optional_cookies if has_css?("#cookie-consent-banner", wait: 3)
    find(".map-point-list summary").click

    assert_selector ".map-point-list li a", text: "Bryggen"
    assert_selector ".map-point-list li a", text: "Fløyen"

    fill_in "map-search", with: "bryggen"
    assert_no_selector ".map-point-list li", text: "Fløyen"

    fill_in "map-search", with: ""
    expose_refetch
    refetch(Bounds.new(south: 60.3949, west: 5.3420, north: 60.3952, east: 5.3440))
    assert_no_selector ".map-point-list li", text: "Bryggen"
    assert_selector ".map-point-list li a", text: "Fløyen"
  end
end
