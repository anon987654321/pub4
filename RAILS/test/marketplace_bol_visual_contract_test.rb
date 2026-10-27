# frozen_string_literal: true

require "minitest/autorun"

class MarketplaceBolVisualContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  BRGEN = File.join(ROOT, "brgen")
  NAV = File.join(BRGEN, "app/views/shared/_storefront_nav_bar.html.erb")
  INDEX = File.join(ROOT, "brgen_marketplace/app/views/marketplace/listings/index.html.erb")
  SHOW = File.join(ROOT, "brgen_marketplace/app/views/marketplace/listings/show.html.erb")
  CSS = File.join(BRGEN, "app/assets/stylesheets/application.scss")
  HEADER_CSS = File.join(BRGEN, "app/assets/stylesheets/_brgen_shared_marketplace_header.scss")
  CITY_CAMPAIGNS_CSS = File.join(BRGEN, "app/assets/stylesheets/_brgen_shared_city_campaigns.scss")
  LOGO_CONTROLLER = File.join(ROOT, "brgen_marketplace", "app/javascript/controllers/marketplace_logo_controller.js")

  def test_marketplace_uses_the_dedicated_bol_header
    nav = File.read(NAV)

    assert_includes nav, 'class="storefront-nav--bol"'
    assert_includes nav, "storefront-bol-brand"
    assert_includes nav, "storefront-bol-search"
    assert_includes nav, "storefront-bol-mainnav"
    assert_includes nav, "storefront-bol-categories"
    assert_includes nav, "storefront-bol-mega"
  end

  def test_storefront_tokens_are_scoped_to_marketplace_and_takeaway
    shell = File.read(File.join(BRGEN, "app/assets/stylesheets/_brgen_vertical_shell.scss"))
    shared = shell.split(":is(body.vertical-marketplace, body.vertical-takeaway) {", 2).last
    refute_nil shared, "the storefront token block must apply to both verticals"
    declarations = shared.split("\n}", 2).first

    %w[--store-ink --store-page --store-rule --store-well --store-text-meta
       --store-text-heading --store-text-price --store-text-action --store-text-brand
       --store-text-brand-compact --store-text-hero-compact --store-text-glyph
       --store-icon-size].each do |token|
      assert_match(/#{Regexp.escape(token)}\s*:/, declarations, "#{token} must be shared by both storefronts")
    end

    takeaway = shell.split("body.vertical-takeaway {", 2).last.split("\n}", 2).first
    assert_includes takeaway, "--font-ad: var(--font);",
                    "the legacy takeaway display face must remain scoped to takeaway"
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

  def test_compact_category_menu_starts_below_the_full_header_stack
    header = File.read(HEADER_CSS)

    assert_match(/--bol-utility-block:\s*calc\(36px\s*\+\s*var\(--safe-top\)\);/, header,
                 "the utility block must include the notch inset before downstream menu geometry is derived")
    catalog = File.read(File.join(BRGEN, "app/assets/stylesheets/_brgen_shared_marketplace_catalog.scss"))
    utility = catalog.match(/body\.vertical-marketplace \.storefront-utility--bol\s*\{([^}]*)\}/m)&.[](1)
    assert utility, "the utility strip must have one base geometry rule"
    assert_match(/padding-block-start:\s*var\(--safe-top\)/, utility)
    assert_match(/padding-inline-start:\s*calc\(var\(--bol-gutter\)\s*\+\s*var\(--safe-left\)\)/, utility)
    assert_match(/padding-inline-end:\s*calc\(var\(--bol-gutter\)\s*\+\s*var\(--safe-right\)\)/, utility)
    campaigns = File.read(CITY_CAMPAIGNS_CSS)
    assert_includes campaigns, "min-height: var(--bol-utility-block);",
                    "the later campaign module must not override the header's utility-height token"
    assert_match(/--bol-mainnav-block:\s*48px;/, header)
    assert_match(/--bol-brand-row-block:\s*48px;/, header)
    assert_match(/--bol-search-control-block:\s*44px;/, header)
    assert_match(/--bol-search-row-gap:\s*8px;/, header)
    assert_match(/--bol-compact-header-padding:\s*8px;/, header)
    assert_match(
      /--bol-compact-header-block:\s*calc\(\s*var\(--bol-brand-row-block\)\s*\+\s*var\(--bol-search-control-block\)\s*\+\s*var\(--bol-search-row-gap\)\s*\+\s*var\(--bol-compact-header-padding\)\s*\+\s*var\(--bol-compact-header-padding\)\s*\);/m,
      header
    )
    assert_match(
      /--bol-compact-mega-top:\s*calc\(\s*var\(--bol-utility-block\)\s*\+\s*var\(--bol-compact-header-block\)\s*\+\s*var\(--bol-mainnav-block\)\s*\);/m,
      header
    )

    compact = header.split("@media (min-width: 768px)", 2).first
    menu = compact&.match(/body\.vertical-marketplace \.storefront-bol-mega\s*\{([^}]*)\}/m)&.[](1)
    assert menu, "compact menu geometry must exist before viewport-specific refinements"
    assert_match(/position:\s*fixed;/, menu)
    assert_match(/inset-block-start:\s*var\(--bol-compact-mega-top\);/, menu)
    assert_match(/max-height:\s*min\(65vh,\s*calc\(100dvh\s*-\s*var\(--bol-compact-mega-top\)\s*-\s*var\(--space-4\)\)\);/, menu,
                 "the category menu must fit the viewport remaining below the header")

    mobile = compact
    assert_match(/storefront-bol-mega\s*\{[^}]*grid-template-columns:\s*repeat\(2, minmax\(0, 1fr\)\);/m, mobile)

    # Each term must remain attached to the physical box it sizes, so a taller
    # search row cannot silently desynchronise the fixed panel's start position.
    assert_includes header, "min-height: var(--bol-utility-block);"
    assert_includes header, "min-height: var(--bol-mainnav-block);"
    assert_includes header, "min-height: var(--bol-brand-row-block);"
    assert_includes header, "height: var(--bol-search-control-block);"
    assert_includes header, "padding-top: var(--bol-search-row-gap);"
    assert_includes header, "padding: var(--bol-compact-header-padding) var(--bol-gutter);"
  end

  def test_marketplace_hero_has_one_responsive_geometry_owner
    campaigns = File.read(CITY_CAMPAIGNS_CSS)
    commerce = File.read(File.join(BRGEN, "app/assets/stylesheets/_brgen_shared_marketplace_commerce.scss"))

    refute_includes campaigns, "min-height: 240px;",
                    "the late campaign layer must not replace the fluid hero media height"
    refute_includes campaigns, "padding: 24px;",
                    "the late campaign layer must not override the commerce hero copy padding"
    refute_includes campaigns, "clamp(2rem, 10vw, 3rem)",
                    "the campaign layer must not redefine the hero headline scale"
    refute_includes campaigns, "clamp(2rem, 9vw, 3rem)",
                    "the campaign layer must not redefine the product headline scale"

    assert_includes commerce, "order: -1;"
    assert_includes commerce, "min-height: min(78vw, 420px);"
    assert_includes commerce, "padding: 28px 20px;"
    assert_includes commerce, "font-size: var(--store-text-hero-compact);"
    assert_includes commerce, "font-size: clamp(2rem, 9vw, 3rem);"
  end

  def test_tablet_storefront_header_stacks_until_the_canonical_desktop_edge
    header = File.read(HEADER_CSS)
    compact = header.split("@media (min-width: 1024px)", 2).first
    assert compact, "mobile-first compact header styles must exist"
    assert_match(/grid-template-columns:\s*minmax\(0, 1fr\) auto;/, compact)
    assert_match(/storefront-bol-deliver\s*\{[^}]*display:\s*none;/m, compact)
    assert_match(/storefront-bol-search\s*\{[^}]*grid-column:\s*1\s*\/\s*-1;[^}]*grid-row:\s*2;/m, compact)
    assert_match(/storefront-bol-mainnav\s*\{[^}]*overflow-x:\s*auto;/m, compact)
    assert_match(/storefront-bol-mega\s*\{[^}]*position:\s*fixed;[^}]*inset-block-start:\s*var\(--bol-compact-mega-top\);/m, compact)

    desktop = header.split("@media (min-width: 1024px)", 2).last
    assert_match(/grid-template-columns:\s*176px 168px minmax\(320px, 1fr\) auto;/, desktop)
    assert_match(/storefront-bol-deliver\s*\{[^}]*display:\s*inline-flex;/m, desktop)
    assert_match(/storefront-bol-mega\s*\{[^}]*position:\s*absolute;/m, desktop)
  end


  def test_logo_falls_back_to_a_visible_static_state_when_animation_loading_fails
    controller = File.read(LOGO_CONTROLLER)
    connect = controller.split("  connect() {", 2).last&.split("\n  disconnect()", 2)&.first

    assert connect, "marketplace logo connection lifecycle must exist"
    assert_includes controller, ".catch(() => null)",
                    "the optional animation CDN must remain a recoverable dependency"
    assert_match(/if \(!anime\) \{\s*this\.#staticEndState\(\)\s*return/m, connect,
                 "failed animation loading must reveal the cart and count instead of leaving them hidden")
    assert_includes controller, "this.numberTarget.textContent = \"9+\"",
                    "the static state must retain a legible cart count"
  end

  def test_logo_burst_spans_keep_their_shared_positioning_rule
    controller = File.read(LOGO_CONTROLLER)
    styles = File.read(File.join(BRGEN, "app/assets/stylesheets/_brgen_marketplace.scss"))

    assert_includes controller, 'this.bannerTarget.querySelectorAll(":scope > span")',
                    "the burst animates every direct child span, including the starter plus"
    assert_match(/\.marketplace \.banner\s*>\s*span\s*\{/, styles)
    assert_match(/#logoWrapper \.marketplace \.banner\s*>\s*span\s*\{/, styles)
  end

  def test_bol_geometry_tokens_are_explicit
    catalog = File.read(File.join(BRGEN, "app/assets/stylesheets/_brgen_shared_marketplace_catalog.scss"))
    header = File.read(HEADER_CSS)
    commerce = File.read(File.join(BRGEN, "app/assets/stylesheets/_brgen_shared_marketplace_commerce.scss"))

    # The accent is the canonical source of the marketplace blue; a fixed
    # second navy would drift from the operator's declared vertical palette.
    assert_includes catalog, "--bol-blue: var(--accent);"
    assert_includes catalog, "--bol-max: 1248px;"
    assert_includes header, "grid-template-columns: 176px 168px minmax(320px, 1fr) auto;"
    assert_includes catalog, "grid-template-columns: 232px minmax(0, 1fr);"
  end
end
