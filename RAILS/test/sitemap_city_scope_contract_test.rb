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
  ROOT = File.expand_path("../brgen", __dir__)
  CONTROLLER = File.join(ROOT, "app/controllers/sitemaps_controller.rb")

  def source
    @source ||= File.read(CONTROLLER)
  end

  def test_sitemap_queries_name_the_city
    assert_includes source, "in_this_city",
                    "sitemap queries must name the city; a tenant default_scope is not a contract a reader can see"
  end

  # in_this_city takes bare classes (Community, Tv::Channel, Place) as well as
  # relations. `klass` is not one of the methods ActiveRecord delegates from a
  # model class to `all`, so dropping the `.all` raises NoMethodError on exactly
  # those three call sites — and only once a city resolves, which no source-text
  # reading of the helper reveals.
  def test_in_this_city_normalises_through_all
    body = source[/def in_this_city.*?\n  end/m]
    refute_nil body, "in_this_city has been renamed or removed"
    assert_includes body, "relation.all",
                    "in_this_city is called with bare model classes; it must go through .all before .klass"
  end

  def test_every_indexable_model_has_an_entries_method
    %w[posts_entries community_entries hashtag_entries tv_entries
       takeaway_entries marketplace_entries maps_entries].each do |method|
      assert_includes source, "def #{method}", "sitemap lost #{method}"
    end
  end

  # Deal has no city_id of its own — it reaches the city through its store — so
  # it must not carry a hand-written column probe that silently opts it out.
  def test_no_per_model_city_column_probes
    refute_match(/column_names\.include\?\("city_id"\)/, source.sub(/def in_this_city.*?\n  end/m, ""),
                 "city scoping belongs in in_this_city, not re-tested per model")
  end
end
