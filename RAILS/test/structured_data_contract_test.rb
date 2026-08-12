# frozen_string_literal: true

# Public show pages that already have a title must also name the city-object
# they sit on: CollectionPage for lists, AggregateRating when reviews exist,
# and a nearby query Google can follow. Source-text so this runs without boot.

require "minitest/autorun"

class StructuredDataContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read_rel(path)
    File.read(File.join(ROOT, path))
  end

  def test_schema_helper_grows_collection_and_rating
    helper = read_rel("shared/app/helpers/schema_helper.rb")
    assert_includes helper, "def collection_page_schema"
    assert_includes helper, "CollectionPage"
    assert_includes helper, "def aggregate_rating_snippet"
    assert_includes helper, "AggregateRating"
    assert_includes helper, "organization_snippet"
  end

  def test_community_and_hashtag_emit_collection_json_ld
    community = read_rel("brgen/app/views/communities/show.html.erb")
    hashtag = read_rel("brgen/app/views/hashtags/show.html.erb")
    assert_includes community, "collection_page_schema"
    assert_includes community, "breadcrumb_json_ld"
    assert_includes hashtag, "collection_page_schema"
    assert_includes hashtag, "breadcrumb_json_ld"
  end

  def test_show_pages_ask_for_nearby_neighbours
    listing = read_rel("brgen/engines/marketplace/app/controllers/marketplace/listings_controller.rb")
    restaurant = read_rel("brgen/engines/takeaway/app/controllers/takeaway/restaurants_controller.rb")
    place = read_rel("brgen/engines/maps/app/controllers/maps/places_controller.rb")
    assert_includes listing, "nearby_listings_for"
    assert_includes restaurant, "nearby_restaurants_for"
    assert_includes place, "nearby_places_for"
    assert_includes listing, ".nearby("
    assert_includes restaurant, ".nearby("
    assert_includes place, ".nearby("
  end
end
