# frozen_string_literal: true

require "yaml"
require "minitest/autorun"
require_relative "engine_roots"
require_relative "support/stylesheet_modules"
require_relative "../../MASTER/tools/master_design"
require_relative "../../MASTER/tools/scss"
require_relative "support/design_contract_sources"

class DesignContractComponentsTest < Minitest::Test
  include DesignContractSources

def test_brgen_composer_uses_starting_style_entry
  app = application_scss("brgen")
  composer = stylesheet_module("brgen", "brgen_composer")
  css = "#{app}\n#{composer}"

    refute_includes css, "composer-drop-in"
    refute_includes css, "composer-backdrop-in"
    assert_includes css, "@starting-style"
    assert_includes css, ".composer[open]::backdrop"
  end

def test_brgen_feature_styles_are_loaded_at_their_original_boundaries
  # One stylesheet per app (operator, 2026-10-28): the merge folded the
  # former partials into these module banners, in the cascade order the old
  # meta.load-css calls held. The order is the contract; the feature rules
  # prove each folded file's text survived the fold.
  assert_equal %w[
    post_gallery
    local_activity
    vertical_promo
    brgen_core_shell
    brgen_navigation
    brgen_messenger
    brgen_composer
    brgen_feed_posts
    brgen_marketplace
    brgen_nearby_channels
    brgen_share_media
    brgen_dating
    brgen_vertical_shell
    brgen_vertical_surfaces
    brgen_city_surfaces
    brgen_shared_overrides brgen_cinema
  ], stylesheet_module_names("brgen").grep_v(/\Asection_\d+\z/), "Brgen module order is a cascade contract"

  # Pairs, not a hash: brgen_city_surfaces pins two rules, and a repeated
  # hash key silently dropped the first.
  expected_rules = [
    ["brgen_marketplace", ".deal-card"],
    ["brgen_vertical_surfaces", ".listing-buy-bar-cta"],
    ["brgen_shared_overrides", "body.vertical-marketplace .store-promo-art-cta"],
    ["brgen_messenger", ".messenger-artifact-pane"],
    ["brgen_composer", ".composer[open]::backdrop"],
    ["brgen_feed_posts", ".feed-action"],
    ["brgen_nearby_channels", ".nearby-alert"],
    ["brgen_share_media", ".media-actions"],
    ["brgen_dating", ".swipe-card"],
    ["brgen_vertical_shell", "body[class*=\"vertical-\"] .feed-header"],
    ["brgen_city_surfaces", ".profile-header"]
  ]
  expected_rules.each do |name, selector|
    assert_includes stylesheet_module("brgen", name), selector, "#{name} lost its representative feature rule"
  end
end

def test_brgen_marketplace_header_uses_mobile_first_breakpoints
  # The former _brgen_shared_marketplace_header.scss folded into the
  # brgen_shared_overrides module in the merge, alongside overrides that
  # are not the storefront header, so the mobile-first contract scopes to
  # the storefront rules themselves: none may sit under a max-width
  # override, and the compact rule stays the base with the 768px one
  # restoring desktop type.
  source = stylesheet_module("brgen", "brgen_shared_overrides")

  # The overrides module also carries the storefront grid plumbing, which is
  # not the header contract; compact-is-base binds the rules that declare the
  # contract itself: the brand type and the action column.
  contract_rules = Operator::ScssRules.matching(source, /storefront-bol-brand|deal-card-actions/)
                                     .select { |rule| rule.body.match?(/--store-text-brand|gap:\s*8px|flex-direction:\s*column/) }

  refute_empty contract_rules, "the storefront header contract rules must still exist"
  contract_rules.each do |rule|
    refute rule.parents.any? { |parent| parent.match?(/@media[^{]*max-width/) },
           "#{rule.selector} sits under a max-width override — compact rules are the base"
  end

  assert_match(/body\.vertical-marketplace \.storefront-bol-brand \{[^}]*font-size: var\(--store-text-brand-compact\)/m, source)
  assert_match(/@media \(min-width: 768px\) \{[\s\S]*?storefront-bol-brand \{[^}]*font-size: var\(--store-text-brand\)/m, source)
  assert_match(/body\.vertical-marketplace #marketplace-listings \.deal-card-actions \{[^}]*gap: 8px/m, source)
  assert_match(/@media \(min-width: 768px\) \{[\s\S]*?deal-card-actions \{[^}]*flex-direction: column/m, source)
end

  def test_promotional_art_is_mobile_first_and_restores_desktop_geometry
    source = File.read(File.join(ROOT, "__shared", "app", "assets", "stylesheets", "_promotional_art.scss"))
    mobile, wide = source.split("@media (min-width: 768px)", 2)

    refute_match(/@media\s*\(\s*max-width\b/, source)
    assert_match(/\.store-promo-art\s*\{[^}]*grid-template-columns:\s*1fr;[^}]*min-height:\s*520px;/m, mobile)
    assert_match(/\.store-promo-art--campaign\s*\{[^}]*grid-template-columns:\s*1fr;/m, mobile)
    assert_match(/\.store-promo-art-copy\s*\{[^}]*justify-content:\s*flex-end;[^}]*min-height:\s*60%;[^}]*padding:\s*24px;[^}]*background:\s*var\(--promo-matte\);/m, mobile)
    assert_match(/\.store-promo-art-media\s*\{[^}]*min-height:\s*300px;[^}]*position:\s*static;/m, mobile)
    assert_match(/\.store-promo-art-image\s*\{[^}]*max-width:\s*82%;[^}]*max-height:\s*300px;/m, mobile)
    assert_match(/\.store-promo-art\s*\{[^}]*grid-template-columns:\s*minmax\(0, 42%\) minmax\(0, 58%\);[^}]*min-height:\s*clamp\(320px, 42vw, 540px\);/m, wide)
    assert_match(/\.store-promo-art--campaign\s*\{[^}]*grid-template-columns:\s*minmax\(0, 40%\) minmax\(0, 60%\);/m, wide)
    assert_match(/\.store-promo-art--tile \.store-promo-art-media,[\s\S]*?\.store-promo-art--portrait \.store-promo-art-media\s*\{[^}]*position:\s*absolute;/m, wide)
  end

  def test_surface_chrome_endgame_is_mobile_first_and_restores_wide_values
    source = File.read(File.join(ROOT, "__shared", "app", "assets", "stylesheets", "_surface_chrome_endgame.scss"))
    refute_match(/@media\s*\(\s*max-width\b/, source,
                 "the shared endgame must use compact defaults and min-width enhancements")

    brgen = source.split("@mixin brgen_precision", 2).last.split("@mixin amber_precision", 2).first
    brgen_mobile, brgen_wide = brgen.split("@media (min-width: 768px)", 2)
    assert_match(/body\[data-layout-contract="shared-layout"\] \.layout > main#main-content\s*\{[^}]*padding-inline:\s*max\(var\(--space-4\), var\(--page-gutter\)\);[^}]*padding-block-end:\s*calc\(var\(--space-16\) \+ env\(safe-area-inset-bottom\)\);/m, brgen_mobile)
    assert_match(/body\[data-layout-contract="shared-layout"\] :is\(\.page-header, \.feed-header\)\s*\{[^}]*margin-block-end:\s*var\(--space-6\);/m, brgen_mobile)
    assert_match(/body\[data-layout-contract="shared-layout"\] \.layout > main#main-content\s*\{[^}]*padding-inline:\s*0;[^}]*padding-block-end:\s*calc\(var\(--space-12\) \+ var\(--safe-bottom\)\);/m, brgen_wide)
    assert_match(/body\[data-layout-contract="shared-layout"\] :is\(\.page-header, \.feed-header\)\s*\{[^}]*margin-block-end:\s*var\(--space-8\);/m, brgen_wide)

    amber = source.split("@mixin amber_precision", 2).last.split("@mixin bsdports", 2).first
    amber_mobile, amber_wide = amber.split("@media (min-width: 768px)", 2)
    assert_match(/body\[data-surface="luxury"\] main#main-content\s*\{[^}]*padding-inline:\s*max\(var\(--space-4\), var\(--page-gutter\)\);[^}]*padding-block-end:\s*calc\(var\(--space-16\) \+ env\(safe-area-inset-bottom\)\);/m, amber_mobile)
    assert_match(/body\[data-surface="luxury"\] \.item-detail-title\s*\{[^}]*max-inline-size:\s*none;[^}]*font-size:\s*clamp\(2\.4rem, 12vw, 4rem\);/m, amber_mobile)
    assert_match(/body\[data-surface="luxury"\] main#main-content\s*\{[^}]*padding-inline:\s*0;[^}]*padding-block-end:\s*calc\(var\(--space-12\) \+ var\(--safe-bottom\)\);/m, amber_wide)
    assert_match(/body\[data-surface="luxury"\] \.item-detail-title\s*\{[^}]*max-inline-size:\s*12ch;[^}]*font-size:\s*clamp\(2\.4rem, 5vw, 5rem\);/m, amber_wide)

    bsd = source.split("@mixin bsdports", 2).last
    bsd_mobile, bsd_wide = bsd.split("@media (min-width: 768px)", 2)
    assert_match(/body\.wscons main#main-content\s*\{[^}]*padding-inline:\s*max\(var\(--space-4\), var\(--page-gutter\)\);[^}]*padding-block:\s*var\(--space-8\) calc\(var\(--space-16\) \+ env\(safe-area-inset-bottom\)\);/m, bsd_mobile)
    assert_match(/body\.wscons \.port-row\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\);/m, bsd_mobile)
    assert_match(/body\.wscons \.install-panel \[data-controller="clipboard"\]\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\);/m, bsd_mobile)
    assert_match(/body\.wscons main#main-content\s*\{[^}]*padding-inline:\s*var\(--page-gutter\);[^}]*padding-block:\s*var\(--space-8\) var\(--space-16\);/m, bsd_wide)
    assert_match(/body\.wscons \.port-row\s*\{[^}]*grid-template-columns:\s*none;/m, bsd_wide)
    assert_match(/body\.wscons \.install-panel \[data-controller="clipboard"\]\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\) auto;/m, bsd_wide)
  end

  def test_shared_affiliate_feed_is_mobile_first
    source = File.read(File.join(ROOT, "__shared", "app", "assets", "stylesheets", "_affiliate_feed_unit.scss"))
    mobile = source.split("@media (min-width: 480px)", 2).first

    refute_match(/@media\s*\(\s*max-width\b/, source)
    assert_match(/\.affiliate_feed_unit\s*\{[^}]*padding:\s*var\(--space-2\);/m, mobile)
    assert_match(/\.affiliate_feed_grid\s*\{[^}]*grid-template-columns:\s*repeat\(2, minmax\(0, 1fr\)\);[^}]*gap:\s*var\(--space-2\);/m, mobile)
    assert_match(/@media \(min-width: 480px\) \{[\s\S]*?\.affiliate_feed_unit\s*\{[^}]*padding:\s*var\(--space-3\);/m, source)
    assert_match(/@media \(min-width: 480px\) \{[\s\S]*?\.affiliate_feed_grid\s*\{[^}]*gap:\s*var\(--space-3\);/m, source)
    assert_match(/@media \(min-width: 480px\) \{[\s\S]*?\.affiliate_feed_unit--brgen\s*\{[^}]*margin-inline:\s*auto;/m, source)
    assert_match(/@media \(min-width: 768px\) \{[\s\S]*?\.affiliate_feed_grid\s*\{[^}]*grid-template-columns:\s*repeat\(4, minmax\(0, 1fr\)\)/m, source)
  end

  def test_post_voting_compact_gap_is_mobile_first
    source = File.read(File.join(ROOT, "__shared", "app", "assets", "stylesheets", "_post_voting.scss"))

    # The base rule sits at column 0 (outside any query); the wider gap is the
    # 480px override. Splitting at the file's first 480px query missed the rule.
    refute_match(/@media\s*\(\s*max-width\b/, source)
    assert_match(/^\.post-reading-layout\s*\{[^}]*gap:\s*var\(--space-2\);/m, source)
    assert_match(/@media \(min-width: 480px\) \{\s*\.post-reading-layout\s*\{[^}]*gap:\s*var\(--space-3\);/m, source)
  end

def test_brgen_marketplace_badge_offsets_are_valid_css
  # The former _brgen_marketplace.scss is now the brgen_marketplace module.
  source = stylesheet_module("brgen", "brgen_marketplace")

    refute_match(/top:\s*--\d+px\s*;/, source, "a negative offset is written with one minus sign")
    assert_match(/\.number_animate\s*\{[^}]*top:\s*-32px\s*;/m, source)
    assert_match(/#logoWrapper\s+\.number_animate\s*\{[^}]*top:\s*-16px\s*;/m, source)
  end

  def test_brgen_mounts_theme_bootstrap_once_in_head
    layout = File.read(File.join(ROOT, "brgen", "app", "views", "layouts", "application.html.erb"))
    copies = layout.scan(/render "shared\/theme_bootstrap"/).size

    assert_equal 1, copies
    bootstrap = layout.index('render "shared/theme_bootstrap"')
    assert bootstrap < layout.index("</head>"), "brgen theme bootstrap must run before first paint"
    refute bootstrap > layout.index("<body"), "brgen must not bootstrap the theme again in the body"
  end

  def test_theme_bootstrap_partial_sets_dataset_before_paint
    partial = File.read(THEME_BOOTSTRAP)
    assert_includes partial, "document.documentElement.dataset.theme"
    assert_includes partial, "localStorage.getItem"
  end

  def test_bottom_sheet_controller_shared
    js = File.read(BOTTOM_SHEET_JS)
    boot = File.read(STIMULUS_BOOT_JS)
    importmap = File.read(IMPORTMAP_BASELINE)
    modal = File.read(MODAL_SCSS)

    # The targets it must have, not the exact spelling of the line: pinning the
    # whole array meant adding a target failed a test about sharing the
    # controller, which is not what this asserts.
    %w[sheet backdrop].each { |target| assert_match(/static targets = \[[^\]]*"#{target}"/, js) }
    assert_includes js, "pointerDown(event)"

    # Closed, the sheet must be out of the tab order and the accessibility tree.
    # translateY(100%) alone only moves it off screen, which left an invisible
    # menu in the tab order of every page.
    assert_match(/\.mobile-sheet\s*\{[^}]*visibility:\s*hidden/m, modal)
    assert_match(/\.mobile-sheet\[data-level="1"\][^{]*\{[^}]*visibility:\s*visible/m, modal)
    assert_includes boot, 'import BottomSheet from "pub4/bottom_sheet"'
    assert_includes boot, 'application.register("bottom-sheet", BottomSheet)'
    assert_includes importmap, 'pin "pub4/bottom_sheet", to: "bottom_sheet_controller.js"'
    assert_includes modal, ".mobile-sheet-backdrop"
    assert_includes modal, ".dialog"
  end

  def test_brgen_emoji_actions_use_the_shared_local_token
    source = stylesheet_source("brgen")
    assert_includes source, '--font-emoji: "Twemoji Mozilla", "Apple Color Emoji", "Segoe UI Emoji", sans-serif;'
    assert_includes source, ".compose-actions span { font-family: var(--font-emoji); }"
  end

  def test_action_controller_posts_body
    js = File.read(ACTION_JS)
    bar = File.read(ACTION_BAR)
    assert_includes js, "URLSearchParams"
    assert_includes js, "_notify(this.errorMessageValue)"
    assert_includes js, 'toast.dataset.controller = "toast"'
    assert_includes bar, 'data-action-error-message-value="<%= t("actions.action_failed") %>"'
  end

  def test_shared_ui_helper_initializer_registered
    engine = File.read(ENGINE_RB)
    assert_includes engine, 'initializer "shared.ui_helper"'
    assert_includes engine, "helper Shared::UiHelper"
  end

  def test_action_bar_contract
    partial = File.read(ACTION_BAR)
    # The wiring, not the literal. The like button gained `popover` alongside
    # `action`, and a Stimulus controller list is unordered and open-ended, so an
    # exact-string assertion fails on a legitimate second controller while still
    # passing if `action` were renamed to something with the same prefix.
    assert_match(/data-controller="[^"]*\baction\b[^"]*"/, partial)
    assert_includes partial, 'data-clipboard-target="source"'
    assert_includes partial, 'like_count.positive? ? like_count : ""'
    assert File.file?(ICON_PARTIAL)
    %w[reply repost like share].each do |name|
      assert File.file?(File.join(SHARED, "app", "views", "shared", "icons", "_#{name}.html.erb")),
             "missing icons/_#{name}.html.erb"
    end
  end

  def test_reply_icon_is_directional_and_not_the_messages_bubble
    icons = File.join(SHARED, "app", "views", "shared", "icons")
    reply = File.read(File.join(icons, "_reply.html.erb"))
    messages = File.read(File.join(icons, "_messages.html.erb"))

    refute_equal messages, reply
    assert_includes reply, '<path d="m9 17-5-5 5-5" />'
    assert_includes reply, '<path d="M20 18v-2a4 4 0 0 0-4-4H4" />'
  end

  def test_takeaway_restaurant_cover_styles_fill_wells_and_bound_previews
    scss = File.read(File.join(ROOT, "brgen", "app", "assets", "stylesheets", "_brgen_marketplace.scss"))

    assert_match(/\.deal-card-img img\.restaurant-cover-image\s*\{[^}]*object-fit:\s*cover/, scss)
    # Bounded and reserved: an 18rem-wide 3:2 box caps the preview at 12rem
    # tall and holds its space before the image loads (layout stability).
    assert_match(/\.restaurant-cover-preview\s*\{[^}]*inline-size:\s*min\(100%,\s*18rem\)/, scss)
    assert_match(/\.restaurant-cover-preview\s*\{[^}]*aspect-ratio:\s*3\s*\/\s*2/, scss)
  end

  def test_web_vitals_wired
    hotwire = File.read(HOTWIRE_JS)
    fleet = File.read(FLEET_ROUTES)
    controller = File.join(SHARED, "app", "controllers", "web_vitals_controller.rb")

    assert File.file?(controller)
    assert_includes hotwire, "bootWebVitalsSampling"
    assert_includes hotwire, 'sendBeacon("/web_vitals"'
    assert_includes fleet, 'post "web_vitals", to: "web_vitals#create"'
  end

  def test_stack_forwards_modal
    stack = File.read(File.join(SHARED, "app", "assets", "stylesheets", "_stack.scss"))
    assert_includes stack, '@forward "modal"'
  end

  def test_compiled_css_no_box_shadow_in_shared_x_builds
    APPS.each do |app|
      css = compiled_css_path(app)
      next unless File.file?(css)

      # Only flag shared x- partial fingerprints — apps may have legacy exceptions.
      body = File.read(css)
      # Soft check: x-action / mobile-sheet rules should not introduce box-shadow
      if body.include?(".mobile-sheet")
        sheet_chunk = body[/\.mobile-sheet[^{]*\{[^}]+\}/m]
        refute_match(/box-shadow/i, sheet_chunk.to_s, "#{app} mobile-sheet has box-shadow")
      end
    end
  end

  def test_tap_floor_use_sites_read_the_token
    leftovers = tap_floor_stylesheets.flat_map do |path|
      File.readlines(path, encoding: "UTF-8").each_with_index.filter_map do |line, index|
        next if line.match?(/\A\s*(\/\/|\/\*|\*)/)
        next if line.match?(/--(?:tap-min|bar-height|face-bar-height|tab-bar-h)\s*:/)

        next unless line.match?(TAP_FLOOR_LITERAL)

        repo = File.expand_path("..", ROOT)
        "#{path.sub("#{repo}/", "").sub("#{ROOT}/", "")}:#{index + 1}: #{line.strip}"
      end
    end

    assert_empty leftovers,
                 "tap-floor literals must be var(--tap-min) — same 44px, named:\n  #{leftovers.join("\n  ")}"
  end

  private

  def test_brgen_active_navigation_uses_the_semantic_signal_without_repainting_the_brand
    typography = File.read(File.join(ROOT, "brgen/app/assets/stylesheets/_brgen_shared_typography.scss"))
    feed = File.read(File.join(ROOT, "brgen/app/assets/stylesheets/_brgen_shared_media_feed.scss"))
    tokens = Operator::MasterDesign.tokens.fetch("visual_identity")

    assert_includes typography, "border-block-end-color: var(--pub4-signal);"
    assert_includes typography, 'html[data-theme="light"] .home-feed-view.is-active'
    assert_includes typography, "border-block-end-color: var(--pub4-signal-on-light);"
    assert_includes feed, "border-block-end: 2px solid var(--pub4-signal);"
    assert_includes feed, 'html[data-theme="light"] .post-progressive-indicator.is-active'
    assert_equal "#C8F55F", tokens.fetch("signal")
    assert_equal "#50630A", tokens.fetch("signal_on_light")
    # The city header and its identity colours remain app-owned; only the
    # selected marker receives the global signal.
    refute_match(/--brgen-header-bg:\s*var\(--pub4-signal\)/, File.read(File.join(ROOT, "brgen/app/assets/stylesheets/application.scss")))
  end
end
