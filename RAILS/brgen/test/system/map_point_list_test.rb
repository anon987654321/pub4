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

  # No MapLibre bundle loads, so the canvas is the list fallback. Fixed and
  # full-height, it squeezed each card below its own text and ran under the
  # search; in the page flow every card holds its text and starts below the HUD.
  test "the list fallback sits below the HUD and every card holds its text" do
    visit_city("maps", "/")
    decline_optional_cookies if has_css?("#cookie-consent-banner", wait: 3)
    assert_selector ".map-fallback a", text: "Bryggen"

    hud_bottom = evaluate_script("document.querySelector('.map-hud').getBoundingClientRect().bottom")
    first_top = evaluate_script("document.querySelector('.map-fallback a').getBoundingClientRect().top")
    spilled = evaluate_script("[...document.querySelectorAll('.map-fallback a')]" \
                              ".filter((card) => card.scrollHeight > card.clientHeight + 1).length")
    assert_operator first_top, :>=, hud_bottom, "the first card starts below the HUD"
    assert_equal 0, spilled, "no card is squeezed below its own text"
  end

  # The places search ran full bleed at desktop width beside a 720px list.
  test "the places search shares the list's column" do
    visit_city("maps", "/places")
    assert_selector ".place-card", text: "Bryggen"

    edges = lambda do |selector|
      evaluate_script("(r => [r.left, r.right])(document.querySelector(arguments[0]).getBoundingClientRect())",
                      selector)
    end
    assert_equal edges.call(".place-card").map(&:round), edges.call("main > .search").map(&:round)
  end
end
