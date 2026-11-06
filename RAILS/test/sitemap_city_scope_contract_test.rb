# frozen_string_literal: true

# brgen serves one app on 44 city domains, and the sitemap is the one surface
# that hands a crawler a list of URLs with no request context around it. A
# sitemap that forgets the city is how oshlo.no came to list Bergen's posts.
#
# ActsAsTenant does scope the CityTenantable models, so the scoping is real
# without this — but a default_scope is invisible at the call site, and the two
# models reached through an association (Tv::Video via its channel,
# Marketplace::Deal via its store) are not covered by it at all. So the contract
# is that the controller *names* the city in its queries, where a reader and a
# reviewer can both see it.
#
# Source-text assertions, deliberately: this runs under bare ruby with no app
# bundle, alongside city_copy_contract_test.rb.

require "minitest/autorun"

class SitemapCityScopeContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  CONTROLLER = File.join(ROOT, "brgen/app/controllers/sitemaps_controller.rb")

  # Every city-owned model the sitemap lists, and where its city comes from.
  # nil means global by design and must NOT be scoped.
  SCOPED = {
    "Post.hot" => :own, "Community" => :own, "Tv::Channel.publicly_visible" => :own,
    "Playlist::Playlist.public_playlists" => :own, "Playlist::Set.publicly_listed" => :parent,
    "Takeaway::Restaurant.indexable" => :own, "Marketplace::Store.publicly_visible" => :own,
    "Marketplace::Listing.publicly_visible" => :own, "Place" => :own,
    "Tv::Video.publicly_visible" => :parent, "Marketplace::Deal.live" => :parent,
  }.freeze

  def source
    @source ||= File.read(CONTROLLER)
  end

  def test_every_city_owned_relation_is_scoped_to_the_current_city
    SCOPED.each_key do |relation|
      assert_includes source, "#{relation}.in_current_city",
                      "#{relation} is listed in the sitemap without naming the city; " \
                      "a tenant default_scope is not a contract a reader can see, " \
                      "and the two :parent models have no default scope at all"
    end
  end

  # The models with no city_id of their own. Without a scope they are simply
  # unscoped, which is how every city's sitemap came to list every city's deals.
  def test_parent_tenanted_models_declare_how_they_reach_a_city
    {
      "brgen_radio/tv/app/models/concerns/tv/channel_tenanted.rb" => "tenanted_through :channel",
      "brgen_marketplace/app/models/marketplace/deal.rb" => "tenanted_through :listing",
      "brgen_radio/playlist/app/models/playlist/set.rb" => "scope :in_current_city",
    }.each do |path, declaration|
      assert_includes File.read(File.join(ROOT, path)), declaration,
                      "#{path} lost its city derivation"
    end
  end

  # Categories are global, but a city's category page is only offered to a
  # crawler when that city has listings in it: the count that decides it is
  # taken over the city's own listings, and the page itself says noindex below
  # the same threshold, so the sitemap and the page cannot disagree.
  def test_category_pages_are_offered_per_city_and_only_when_not_thin
    assert_includes source, "Marketplace::Category.indexable_in_current_city"
    category = File.read(File.join(ROOT, "brgen_marketplace/app/models/marketplace/category.rb"))
    assert_includes category, "Marketplace::Listing.publicly_visible.in_current_city"
    page = File.read(File.join(ROOT, "brgen_marketplace/app/views/marketplace/categories/show.html.erb"))
    assert_includes page, "@category.indexable_with?(@pagy.count)"
    assert_includes page, 't("marketplace.category_description"'
  end

  def test_city_scoping_is_one_mechanism_not_a_controller_helper
    refute_includes source, "in_this_city",
                    "city scoping belongs on the models (CityScoped / TenantedThrough), not re-derived in the controller"
    refute_match(/column_names\.include\?\("city_id"\)/, source,
                 "a runtime schema probe cannot tell 'not tenanted' from 'tenanted through a parent'")
  end

  def test_every_indexable_model_has_an_entries_method
    %w[posts_entries community_entries hashtag_entries user_entries tv_entries
       food_entries marketplace_entries maps_entries].each do |method|
      assert_includes source, "def #{method}", "sitemap lost #{method}"
    end
  end
end
