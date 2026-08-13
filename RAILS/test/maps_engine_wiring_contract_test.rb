# frozen_string_literal: true

# maps became a mountable engine on 2026-08-12, the last of brgen's verticals to
# move. The move is the thing that breaks quietly: tooling that globs
# <app>/app/** stops seeing engine code, and a check that stops looking still
# passes, so a falling finding count reads as improvement rather than blindness.
#
# These assertions were in brgen/test/services/deploy_backlog_test.rb, which is
# at its length ceiling. That file's ratchet asks for a split rather than a
# raise, and a per-engine contract is a better home than a shared backlog:
# the next vertical to move gets a file to copy instead of a method to append.
#
# Source-text assertions, under bare ruby with no app bundle.

require "minitest/autorun"

class MapsEngineWiringContractTest < Minitest::Test
  ROOT = File.expand_path("../brgen", __dir__)

  def read(relative)
    path = File.join(ROOT, relative)
    assert File.file?(path), "#{relative} is gone — the engine moved again"
    File.read(path)
  end

  def test_the_engine_is_mounted
    assert_includes read("config/routes.rb"), "mount Maps::Engine",
                    "an unmounted engine routes nothing, and every path helper below still resolves"
  end

  def test_places_browse_paginates_and_serves_html
    controller = read("engines/maps/app/controllers/maps/places_controller.rb")
    assert_includes controller, "format.html"
    assert_includes controller, "@pagy, @places = pagy"
  end

  def test_places_infinite_scroll_is_wired_end_to_end
    assert_includes read("engines/maps/app/views/maps/places/_live_search_results.html.erb"),
                    "PlacesInfiniteScrollReflex#load_more"
    assert_includes read("app/reflexes/places_infinite_scroll_reflex.rb"), "maps/places/card",
                    "the reflex renders a card partial that lives in the engine"
  end

  def test_places_are_reachable_from_index_and_home
    %w[engines/maps/app/views/maps/places/index.html.erb
       engines/maps/app/views/maps/home/index.html.erb].each do |view|
      assert_includes read(view), "places_path", "#{view} lost its link into places"
    end
  end

  def test_place_show_offers_a_check_in
    assert_includes read("engines/maps/app/views/maps/places/show.html.erb"), "check_in_place_path"
  end

  def test_map_home_centers_on_the_current_city_not_bergen
    home = read("engines/maps/app/views/maps/home/index.html.erb")
    controller = read("engines/maps/app/controllers/maps/home_controller.rb")
    refute_includes home, "60.39"
    assert_includes home, "@map_center_lat"
    assert_includes controller, "city&.latitude"
    assert_includes home, 't("maps.aria_map")'
  end
end
