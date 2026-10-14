# frozen_string_literal: true

require "minitest/autorun"

class MarketplaceBolVisualContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  BRGEN = File.join(ROOT, "brgen")
  NAV = File.join(BRGEN, "app/views/shared/_storefront_nav_bar.html.erb")
  INDEX = File.join(BRGEN, "engines/marketplace/app/views/marketplace/listings/index.html.erb")
  SHOW = File.join(BRGEN, "engines/marketplace/app/views/marketplace/listings/show.html.erb")
  CSS = File.join(BRGEN, "app/assets/stylesheets/application.scss")
  HEADER_CSS = File.join(BRGEN, "app/assets/stylesheets/_brgen_shared_marketplace_header.scss")
  CITY_CAMPAIGNS_CSS = File.join(BRGEN, "app/assets/stylesheets/_brgen_shared_city_campaigns.scss")

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

  def test_mobile_category_menu_starts_below_the_full_header_stack
    header = File.read(HEADER_CSS)

    assert_match(/--bol-utility-block:\s*36px;/, header)
    campaigns = File.read(CITY_CAMPAIGNS_CSS)
    assert_includes campaigns, "min-height: var(--bol-utility-block);",
                    "the later campaign module must not override the header's utility-height token"
    assert_match(/--bol-mainnav-block:\s*48px;/, header)
    assert_match(/--bol-brand-row-block:\s*48px;/, header)
    assert_match(/--bol-search-control-block:\s*44px;/, header)
    assert_match(/--bol-search-row-gap:\s*8px;/, header)
    assert_match(/--bol-mobile-header-padding:\s*8px;/, header)
    assert_match(
      /--bol-mobile-header-block:\s*calc\(\s*var\(--bol-brand-row-block\)\s*\+\s*var\(--bol-search-control-block\)\s*\+\s*var\(--bol-search-row-gap\)\s*\+\s*var\(--bol-mobile-header-padding\)\s*\+\s*var\(--bol-mobile-header-padding\)\s*\);/m,
      header
    )
    assert_match(
      /--bol-mobile-mega-top:\s*calc\(\s*var\(--bol-utility-block\)\s*\+\s*var\(--bol-mobile-header-block\)\s*\+\s*var\(--bol-mainnav-block\)\s*\);/m,
      header
    )

    mobile = header.split("@media (max-width: 767px)", 2).last
    menu = mobile&.match(/body\.vertical-marketplace \.storefront-bol-mega\s*\{([^}]*)\}/m)&.[](1)
    assert menu, "mobile menu positioning must stay inside the mobile breakpoint"
    assert_match(/inset-block-start:\s*var\(--bol-mobile-mega-top\);/, menu)
    assert_match(/max-height:\s*min\(65vh,\s*calc\(100dvh\s*-\s*var\(--bol-mobile-mega-top\)\s*-\s*var\(--space-4\)\)\);/, menu,
                 "the category menu must fit the viewport remaining below the header")

    # Each term must remain attached to the physical box it sizes, so a taller
    # search row cannot silently desynchronise the fixed panel's start position.
    assert_includes header, "min-height: var(--bol-utility-block);"
    assert_includes header, "min-height: var(--bol-mainnav-block);"
    assert_includes header, "min-height: var(--bol-brand-row-block);"
    assert_includes header, "height: var(--bol-search-control-block);"
    assert_includes header, "padding-top: var(--bol-search-row-gap);"
    assert_includes header, "padding: var(--bol-mobile-header-padding) var(--bol-gutter);"
  end

  def test_bol_geometry_tokens_are_explicit
    css = File.read(CSS)

    assert_includes css, "--bol-blue: #0000a3;"
    assert_includes css, "--bol-max: 1248px;"
    assert_includes css, "grid-template-columns: 176px 168px minmax(320px, 1fr) auto;"
    assert_includes css, "grid-template-columns: 232px minmax(0, 1fr);"
  end
end
