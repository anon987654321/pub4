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

  def test_sitemapped_profile_emits_person_json_ld
    show = read_rel("brgen/app/views/users/show.html.erb")
    helper = read_rel("shared/app/helpers/schema_helper.rb")
    assert_includes show, "json_ld_for(@user, type: :person)"
    assert_includes helper, "display_name"
  end

  def test_remaining_public_shows_emit_json_ld
    {
      "brgen/engines/tv/app/views/tv/channels/show.html.erb" => "broadcast_channel",
      "brgen/engines/tv/app/views/tv/shows/show.html.erb" => "tv_series",
      "brgen/engines/tv/app/views/tv/live_streams/show.html.erb" => "type: :video",
      "brgen/engines/playlist/app/views/playlist/sets/show.html.erb" => "music_playlist",
    }.each do |path, marker|
      assert_includes read_rel(path), marker, "#{path} still has a title and no structured data"
    end
  end

  def test_community_and_hashtag_emit_collection_json_ld
    community = read_rel("brgen/app/views/communities/show.html.erb")
    hashtag = read_rel("brgen/app/views/hashtags/show.html.erb")
    assert_includes community, "collection_page_schema"
    assert_includes community, "breadcrumb_json_ld"
    assert_includes hashtag, "collection_page_schema"
    assert_includes hashtag, "breadcrumb_json_ld"
  end

  def test_sitemap_lists_public_profiles_in_this_city
    sitemap = read_rel("brgen/app/controllers/sitemaps_controller.rb")
    user = read_rel("brgen/app/models/user.rb")
    assert_includes sitemap, "user_entries"
    assert_includes sitemap, "User.public_profiles"
    assert_includes user, "scope :public_profiles"
    refute_includes sitemap, "Dating::"
  end

  def test_owners_can_attach_a_place
    restaurant = read_rel("brgen/engines/takeaway/app/controllers/takeaway/restaurants_controller.rb")
    store = read_rel("brgen/engines/marketplace/app/controllers/marketplace/stores_controller.rb")
    assert_includes restaurant, ":place_id"
    assert_includes store, ":place_id"
    assert_includes restaurant, "load_city_places"
    assert_includes store, "load_city_places"
    assert File.file?(File.join(ROOT, "brgen/engines/takeaway/app/views/takeaway/restaurants/_place_field.html.erb"))
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
