# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require_relative "../gates/support/page_inventory"
require_relative "../tools/generate_route_manifest"

# PageInventory derived a page's URL from its view filename through a ladder of
# hand-written special cases. Four routes that did not follow the convention --
# bookmarks#index at /saved, and pages#show for privacy/terms/cookies -- made
# page_simulation probe 404s and report them as broken pages. Separately, brgen's
# five verticals became engines and the discovery never followed them, so 57
# full-page views left the simulation with nothing reporting it.
#
# These tests read the committed manifest and the inventory. They boot nothing.
class RouteManifestInventoryTest < Minitest::Test
  def manifest = Deploy::PageInventory.manifest

  def inventory = @inventory ||= Deploy::PageInventory.all

  def find(id) = inventory.find { |page| page[:id] == id }

  def test_manifest_covers_every_app_the_inventory_probes
    assert_equal %w[amber brgen bsdports], manifest.fetch("apps").keys.sort
    manifest["apps"].each_value do |row|
      refute_empty row.fetch("routes"), "an app with no routes resolves nothing"
      assert_match(/\A[0-9a-f]{16}\z/, row.fetch("digest"))
    end
  end

  # The manifest is generated. A stale one resolves confidently and wrongly,
  # which is precisely the failure the filename ladder had.
  def test_manifest_matches_the_routes_it_was_generated_from
    assert_empty Deploy::PageInventory.stale_route_manifests
  end

  def test_routes_beat_the_filename_convention
    {
      "brgen/bookmarks/index" => "/saved",
      "brgen/pages/privacy" => "/privacy",
      "brgen/pages/terms" => "/terms",
      "brgen/pages/cookies" => "/cookies",
    }.each do |id, path|
      page = find(id)
      refute_nil page, "#{id} left the inventory"
      assert_equal path, page[:path], "#{id} resolved to the convention, not the route"
    end
  end

  def test_engine_verticals_are_in_the_inventory
    %w[dating marketplace playlist takeaway tv].each do |vertical|
      pages = inventory.select { |page| page[:id].start_with?("brgen/#{vertical}/") }

      refute_empty pages, "#{vertical} engine views are outside the simulation"
    end
  end

  def test_vertical_roots_carry_their_own_host
    assert_equal "dating.brgen.no", find("brgen/dating/home/index")[:host]
    assert_equal "/", find("brgen/dating/home/index")[:path]
    assert_equal "markedsplass.brgen.no", find("brgen/marketplace/listings/index")[:host]
  end

  # A path with any route parameter cannot be fetched as written. The old test
  # for this only knew :id and :handle, so /tags/:name was probed literally.
  def test_parameterised_paths_are_never_probed_live
    Deploy::PageInventory.guest_liveable.each do |page|
      refute_match(/:\w+/, page[:path], "#{page[:id]} would be fetched with a literal parameter")
    end
  end

  # Every vertical ships a `new` form and each answers 403 to a guest.
  def test_authoring_forms_are_not_guest_surfaces
    %w[brgen/marketplace/stores/new brgen/playlist/hosted_tracks/new brgen/takeaway/restaurants/new].each do |id|
      assert_equal "auth", find(id)[:persona], "#{id} is probed as a guest page"
    end
  end

  def test_sign_in_and_sign_up_stay_guest_reachable
    assert Deploy::PageInventory.guest_open_brgen?("/session/new", "sessions/new")
    assert Deploy::PageInventory.guest_open_brgen?("/registration/new", "registrations/new")
  end

  def test_digest_moves_when_a_route_source_changes
    before = Deploy::RouteManifest.digest("brgen")

    assert_equal before, Deploy::RouteManifest.digest("brgen")
    refute_equal before, Deploy::RouteManifest.digest("amber")
  end
end
