# frozen_string_literal: true

require "minitest/autorun"
require_relative "support/stylesheet_modules"
require_relative "../../MASTER/tools/scss"

class MarketplaceBolVisualContractTest < Minitest::Test
  include StylesheetModules
  ROOT = File.expand_path("..", __dir__)
  BRGEN = File.join(ROOT, "brgen")
  NAV = File.join(BRGEN, "app/views/shared/_storefront_nav_bar.html.erb")
  INDEX = File.join(ROOT, "brgen_marketplace/app/views/marketplace/listings/index.html.erb")
  SHOW = File.join(ROOT, "brgen_marketplace/app/views/marketplace/listings/show.html.erb")
  CSS = File.join(BRGEN, "app/assets/stylesheets/application.scss")
  # One stylesheet per app (operator, 2026-10-28): the former marketplace
  # header and city-campaigns partials folded into the brgen_shared_overrides
  # module; the catalog folded into brgen_marketplace. The slices restore the
  # file boundaries these contracts were written against.
  HEADER_MODULE = ["brgen", "brgen_shared_overrides"].freeze
  CATALOG_MODULE = ["brgen", "brgen_marketplace"].freeze

  def header_css
    stylesheet_module(*HEADER_MODULE)
  end

  def campaigns_css
    stylesheet_module(*HEADER_MODULE)
  end

  def catalog_css
    stylesheet_module(*CATALOG_MODULE)
  end
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
    shell = stylesheet_module("brgen", "brgen_vertical_shell")
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
    header = header_css

    assert_match(/--bol-utility-block:\s*calc\(36px\s*\+\s*var\(--safe-top\)\);/, header,
                 "the utility block must include the notch inset before downstream menu geometry is derived")
    utility = header_css.match(/body\.vertical-marketplace \.storefront-utility--bol\s*\{([^}]*)\}/m)&.[](1)
    assert utility, "the utility strip must have one base geometry rule"
    assert_match(/padding-block-start:\s*var\(--safe-top\)/, utility)
    assert_match(/padding-inline-start:\s*calc\(var\(--bol-gutter\)\s*\+\s*var\(--safe-left\)\)/, utility)
    assert_match(/padding-inline-end:\s*calc\(var\(--bol-gutter\)\s*\+\s*var\(--safe-right\)\)/, utility)
    campaigns = campaigns_css
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

    # The overrides module is a union of former files, so the module-local
    # 768px split is not the menu's own; read the mega rule's media context.
    menu = Operator::ScssRules.rules(header)
                             .find { |rule| rule.selector == "body.vertical-marketplace .storefront-bol-mega" &&
                                            rule.parents.none? { |parent| parent.match?(/min-width/) } }
    assert menu, "compact menu geometry must exist before viewport-specific refinements"
    assert_match(/position:\s*fixed;/, menu.body)
    assert_match(/inset-block-start:\s*var\(--bol-compact-mega-top\);/, menu.body)
    assert_match(/max-height:\s*min\(65vh,\s*calc\(100dvh\s*-\s*var\(--bol-compact-mega-top\)\s*-\s*var\(--space-4\)\)\);/, menu.body,
                 "the category menu must fit the viewport remaining below the header")
    assert_match(/grid-template-columns:\s*repeat\(2, minmax\(0, 1fr\)\);/, menu.body)

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
    campaigns = campaigns_css
    commerce = header_css

    campaign_rules = Operator::ScssRules.matching(campaigns, /store-promo-art/)
    refute_empty campaign_rules, "the campaign layer must still be present"
    campaign_rules.each do |rule|
      refute_includes rule.body, "min-height: 240px;",
                      "the late campaign layer must not replace the fluid hero media height"
      refute_includes rule.body, "padding: 24px;",
                      "the late campaign layer must not override the commerce hero copy padding"
      refute_includes rule.body, "clamp(2rem, 10vw, 3rem)",
                      "the campaign layer must not redefine the hero headline scale"
      refute_includes rule.body, "clamp(2rem, 9vw, 3rem)",
                      "the campaign layer must not redefine the product headline scale"
    end

    assert_includes commerce, "order: -1;"
    assert_includes commerce, "min-height: min(78vw, 420px);"
    assert_includes commerce, "padding: 28px 20px;"
    assert_includes commerce, "font-size: var(--store-text-hero-compact);"
    assert_includes commerce, "font-size: clamp(2rem, 9vw, 3rem);"
  end

  def test_tablet_storefront_header_stacks_until_the_canonical_desktop_edge
    # The overrides module carries several former files, so the file-local
    # media split is gone; the contract reads each rule's own media context.
    header = header_css
    rules = Operator::ScssRules.rules(header)

    compact = rules.select { |rule| rule.parents.none? { |parent| parent.match?(/min-width:\s*1024px/) } }
    top_half = compact.find { |rule| rule.selector.match?(/#navBar\.storefront-nav--bol #topHalf\z/) }
    assert top_half, "the compact header row must exist outside the desktop block"
    assert_match(/grid-template-columns:\s*minmax\(0, 1fr\) auto;/, top_half.body)

    {
      "storefront-bol-deliver" => /display:\s*none;/,
      "storefront-bol-search" => /grid-column:\s*1\s*\/\s*-1;/,
      "storefront-bol-mainnav" => /overflow-x:\s*auto;/,
      "storefront-bol-mega" => /position:\s*fixed;/
    }.each do |surface, shape|
      rule = compact.find { |candidate| candidate.selector.match?(/#{surface}\z/) }
      assert rule, "#{surface} must have one compact rule"
      assert_match(shape, rule.body, "#{surface} compact geometry drifted")
    end

    mega = compact.find { |candidate| candidate.selector == "body.vertical-marketplace .storefront-bol-mega" }
    assert_match(/inset-block-start:\s*var\(--bol-compact-mega-top\);/, mega.body,
                 "the compact menu must hang off the compact header's own measured block")

    desktop = rules.select { |rule| rule.parents.any? { |parent| parent.match?(/min-width:\s*1024px/) } }
    desktop_top = desktop.find { |rule| rule.body.match?(/grid-template-columns:\s*176px 168px minmax\(320px, 1fr\) auto;/) }
    assert desktop_top, "the desktop header row must restore the four-column band"
    deliver = desktop.find { |rule| rule.selector.match?(/storefront-bol-deliver\z/) }
    assert_match(/display:\s*inline-flex;/, deliver.body, "the desktop deliver row must return")
    desktop_mega = desktop.find { |rule| rule.selector == "body.vertical-marketplace .storefront-bol-mega" }
    assert_match(/position:\s*absolute;/, desktop_mega.body, "the desktop menu must anchor to the nav, not the viewport")
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
    styles = catalog_css

    assert_includes controller, 'this.bannerTarget.querySelectorAll(":scope > span")',
                    "the burst animates every direct child span, including the starter plus"
    assert_match(/\.marketplace \.banner\s*>\s*span\s*\{/, styles)
    assert_match(/#logoWrapper \.marketplace \.banner\s*>\s*span\s*\{/, styles)
  end

  def test_bol_geometry_tokens_are_explicit
    catalog = catalog_css
    header = header_css
    commerce = catalog_css

    # The accent is the canonical source of the marketplace blue; a fixed
    # second navy would drift from the operator's declared vertical palette.
    assert_includes header, "--bol-blue: var(--accent);"
    assert_includes header, "--bol-max: 1248px;"
    assert_match(/grid-template-columns:\s*176px 168px minmax\(320px, 1fr\) auto;/, header)
    assert_includes header, "grid-template-columns: 232px minmax(0, 1fr);"
  end
end
