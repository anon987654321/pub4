# frozen_string_literal: true

require "minitest/autorun"
require_relative "../support/source_reader"

# Every surface that scroll-loads, and the wiring each one needs: a reflex
# subclass, a sentinel in the view, and a container the reflex appends into.
#
# These eight tests were spread through deploy_backlog_test.rb, which bundles
# forty unrelated deploy contracts and had grown past its file-length ceiling.
# They are one subject, and the subject most likely to keep growing — five more
# surfaces got a reflex on 2026-08-26 — so they are their own file rather than
# eight more entries in a list of forty.
#
# Reads source as text, like the file they came from: this asserts the wiring
# exists, not that it works. RAILS/test/infinite_scroll_reflex_contract_test.rb
# holds the contract the reflex spine itself has to keep.
class InfiniteScrollWiringTest < Minitest::Test
  include SourceReader

  def test_marketplace_listings_use_stimulus_reflex_infinite_scroll
    partial = read_brgen("app/views/marketplace/listings/_live_search_results.html.erb")
    reflex = read_brgen("app/reflexes/listings_infinite_scroll_reflex.rb")

    assert_includes partial, "ListingsInfiniteScrollReflex#load_more"
    assert_includes partial, "marketplace-listings-sentinel"
    assert_includes reflex, "class ListingsInfiniteScrollReflex"
    assert_includes reflex, "marketplace/listings/card"
  end

  def test_home_feed_uses_stimulus_reflex_infinite_scroll
    home = read_brgen("app/controllers/home_controller.rb")
    partial = read_brgen("app/views/home/_live_search_results.html.erb")
    reflex = read_brgen("app/reflexes/home_infinite_scroll_reflex.rb")

    assert_includes home, "@pagy, @posts = pagy(scope)"
    assert_includes partial, "HomeInfiniteScrollReflex#load_more"
    assert_includes partial, "home-feed-sentinel"
    assert_includes reflex, "Brgen::HomeFeed.scope"
  end

  def test_takeaway_and_tv_indexes_use_infinite_scroll_reflexes
    restaurants = read_brgen("app/views/takeaway/restaurants/_live_search_results.html.erb")
    channels = read_brgen("app/views/tv/channels/_live_search_results.html.erb")

    assert_includes restaurants, "RestaurantsInfiniteScrollReflex#load_more"
    assert_includes restaurants, "takeaway-restaurants-sentinel"
    assert_includes channels, "ChannelsInfiniteScrollReflex#load_more"
    assert_includes channels, "tv-channels-sentinel"
    assert_includes read_source(File.join(ROOT, "brgen/app/reflexes/restaurants_infinite_scroll_reflex.rb")),
                    "takeaway/restaurants/card"
    assert_includes read_source(File.join(ROOT, "brgen/app/reflexes/channels_infinite_scroll_reflex.rb")),
                    "tv/channels/row"
  end

  def test_marketplace_deals_stores_and_playlist_sets_use_infinite_scroll
    deals_partial = read_brgen("app/views/marketplace/deals/_live_search_results.html.erb")
    stores_partial = read_brgen("app/views/marketplace/stores/_live_search_results.html.erb")
    sets_partial = read_brgen("app/views/playlist/sets/_live_search_results.html.erb")

    assert_includes deals_partial, "DealsInfiniteScrollReflex#load_more"
    assert_includes stores_partial, "StoresInfiniteScrollReflex#load_more"
    assert_includes sets_partial, "SetsInfiniteScrollReflex#load_more"
    assert_includes read_brgen("app/controllers/marketplace/deals_controller.rb"), "@pagy, @deals = pagy"
    assert_includes read_brgen("app/controllers/marketplace/stores_controller.rb"), "@pagy, @stores = pagy"
    assert_includes read_brgen("app/controllers/playlist/sets_controller.rb"), "@pagy, @sets = pagy"
    assert_includes read_brgen("app/reflexes/deals_infinite_scroll_reflex.rb"), "marketplace/deals/card"
    assert_includes read_brgen("app/reflexes/stores_infinite_scroll_reflex.rb"), "marketplace/stores/card"
    assert_includes read_brgen("app/reflexes/sets_infinite_scroll_reflex.rb"), "playlist/sets/card"
  end

  def test_communities_infinite_scroll_and_crud_views_are_wired
    partial = read_brgen("app/views/communities/_live_search_results.html.erb")
    controller = read_brgen("app/controllers/communities_controller.rb")

    assert_includes partial, "CommunitiesInfiniteScrollReflex#load_more"
    assert_includes controller, "@pagy, @communities = pagy"
    assert_includes controller, "def edit"
    assert_includes controller, "def update"
    assert_includes controller, "def destroy"
    assert File.file?(File.join(ROOT, "brgen/app/views/communities/edit.html.erb"))
    assert_includes read_brgen("app/reflexes/communities_infinite_scroll_reflex.rb"), "communities/card"
    assert_includes read_source(File.join(ROOT, "brgen/app/assets/stylesheets/_communities.scss")), ".community-list"
  end

  def test_posts_infinite_scroll_preserves_search_query
    partial = read_brgen("app/views/posts/_live_search_results.html.erb")
    reflex = read_brgen("app/reflexes/posts_infinite_scroll_reflex.rb")

    assert_includes partial, "q: params[:q]"
    assert_includes reflex, 'element.dataset["q"]'
    assert_includes reflex, "title LIKE ? OR content LIKE ?"
  end

  def test_secondary_brgen_verticals_use_infinite_scroll_reflexes
    sentinel = read_source(File.join(ROOT, "shared/app/views/shared/_infinite_scroll_sentinel.html.erb"))
    assert_includes sentinel, "data-channel-slug"

    assert_includes read_brgen("app/views/tv/channels/_channel_videos.html.erb"), "ChannelVideosInfiniteScrollReflex#load_more"
    assert_includes read_brgen("app/reflexes/channel_videos_infinite_scroll_reflex.rb"), "tv/videos/tv_video"

    assert_includes read_brgen("app/views/tv/home/_trending_videos.html.erb"), "TrendingVideosInfiniteScrollReflex#load_more"
    assert_includes read_brgen("app/reflexes/trending_videos_infinite_scroll_reflex.rb"), "Tv::Video.trending"

    assert_includes read_brgen("app/views/takeaway/orders/index.html.erb"), "OrdersInfiniteScrollReflex#load_more"
    assert_includes read_brgen("app/reflexes/orders_infinite_scroll_reflex.rb"), "takeaway/orders/order"

    assert_includes read_brgen("app/views/dating/matches/index.html.erb"), "MatchesInfiniteScrollReflex#load_more"
    assert_includes read_brgen("app/reflexes/matches_infinite_scroll_reflex.rb"), "dating/matches/match"

    assert_includes read_brgen("app/views/marketplace/categories/show.html.erb"), "CategoryListingsInfiniteScrollReflex#load_more"
    assert_includes read_brgen("app/reflexes/category_listings_infinite_scroll_reflex.rb"), "marketplace/listings/card"

    assert_includes read_brgen("app/views/tv/shows/index.html.erb"), "ShowsInfiniteScrollReflex#load_more"
    assert_includes read_brgen("app/reflexes/shows_infinite_scroll_reflex.rb"), "tv/shows/card"

    assert_includes read_brgen("app/views/playlist/playlists/_library.html.erb"), "PlaylistsInfiniteScrollReflex#load_more"
    assert_includes read_brgen("app/reflexes/playlists_infinite_scroll_reflex.rb"), "playlist/playlists/row"
    assert_includes read_brgen("app/assets/stylesheets/_vertical_tv.scss"), ".show-grid"
    assert_includes read_brgen("app/assets/stylesheets/_vertical_takeaway.scss"), ".order-list"
    assert_includes read_brgen("app/views/dating/matches/index.html.erb"), "match-list"
  end

  def test_satellite_apps_use_infinite_scroll_reflexes
    sentinel = read_source(File.join(ROOT, "shared/app/views/shared/_infinite_scroll_sentinel.html.erb"))

    assert_includes read_source(File.join(ROOT, "amber/app/views/items/_live_search_results.html.erb")),
                    "ItemsInfiniteScrollReflex#load_more"
    assert_includes read_source(File.join(ROOT, "amber/app/reflexes/items_infinite_scroll_reflex.rb")),
                    "items/item"

    assert_includes read_source(File.join(ROOT, "amber/app/views/outfits/_live_search_results.html.erb")),
                    "OutfitsInfiniteScrollReflex#load_more"
    assert_includes read_source(File.join(ROOT, "amber/app/reflexes/outfits_infinite_scroll_reflex.rb")),
                    "outfits/outfit"

    # The sentinel moved out of _live_search_results and into the _list partial
    # it renders, so asserting on _live_search_results directly went stale even
    # though ports infinite scroll still works. Follow the render instead: the
    # search results must reach the list, and the list must carry the reflex.
    assert_includes read_source(File.join(ROOT, "bsdports/app/views/ports/_live_search_results.html.erb")),
                    "ports/list"
    assert_includes read_source(File.join(ROOT, "bsdports/app/views/ports/_list.html.erb")),
                    "PortsInfiniteScrollReflex#load_more"
    assert_includes read_source(File.join(ROOT, "bsdports/app/reflexes/ports_infinite_scroll_reflex.rb")),
                    "ports/row"

    assert_includes read_source(File.join(ROOT, "bsdports/app/views/maintainers/show.html.erb")),
                    "MaintainerPortsInfiniteScrollReflex#load_more"
    assert_includes sentinel, "data-maintainer-id"
  end
end
