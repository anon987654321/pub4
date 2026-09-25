# frozen_string_literal: true

require "minitest/autorun"

class MarketplaceBolVisualContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  BRGEN = File.join(ROOT, "brgen")
  NAV = File.join(BRGEN, "app/views/shared/_storefront_nav_bar.html.erb")
  INDEX = File.join(BRGEN, "engines/marketplace/app/views/marketplace/listings/index.html.erb")
  SHOW = File.join(BRGEN, "engines/marketplace/app/views/marketplace/listings/show.html.erb")
  CSS = File.join(BRGEN, "app/assets/stylesheets/application.scss")

  def test_marketplace_uses_the_dedicated_bol_header
    nav = File.read(NAV)

    assert_includes nav, 'class="storefront-nav--bol"'
    assert_includes nav, "storefront-bol-brand"
    assert_includes nav, "storefront-bol-search"
    assert_includes nav, "storefront-bol-mainnav"
    assert_includes nav, "storefront-bol-categories"
    assert_includes nav, "storefront-bol-mega"
  end

  def test_catalogue_has_the_bol_discovery_anatomy
    index = File.read(INDEX)

    assert_includes index, "bol-market-hero"
    assert_includes index, "bol-kind-tabs"
    assert_includes index, "bol-catalog-layout"
    assert_includes index, "bol-filter-column"
    assert_includes index, "bol-results-column"
  end

  # The buy box is the listings/_buybox partial the page renders, so the page
  # is read together with it.
  def test_product_page_keeps_the_same_navigation_and_buy_box_anatomy
    show = File.read(SHOW)
    buybox = File.read(File.join(File.dirname(SHOW), "_buybox.html.erb"))

    assert_includes show, "categories: @categories"
    assert_includes show, "store-breadcrumb"
    assert_includes show, "store-pdp"
    assert_includes show, %(render "marketplace/listings/buybox")
    assert_includes buybox, "store-buybox"
  end

  def test_bol_geometry_tokens_are_explicit
    css = File.read(CSS)

    assert_includes css, "--bol-blue: #0000a3;"
    assert_includes css, "--bol-max: 1248px;"
    assert_includes css, "grid-template-columns: 176px 168px minmax(320px, 1fr) auto;"
    assert_includes css, "grid-template-columns: 232px minmax(0, 1fr);"
  end
end
