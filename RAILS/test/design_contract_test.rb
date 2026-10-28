# frozen_string_literal: true

# Recovered / adapted from recover/x-parity-stack (325e3edac).
# Asserts contracts against current main paths (not the obsolete pub4_* renames).
require "yaml"
require "minitest/autorun"
require_relative "engine_roots"
require_relative "../../MASTER/tools/master_design"
require_relative "../../MASTER/tools/scss"

class DesignContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SHARED = File.join(ROOT, "__shared")
  DIALECT_TOKENS_SCSS = File.join(SHARED, "app", "assets", "stylesheets", "_dialect_tokens.scss")
  TOKENS_YML = File.join(SHARED, "design_tokens.yml")
  TOKENS_CSS = File.join(SHARED, "public", "styles", "tokens.css")
  TOKENS_SCSS = File.join(SHARED, "app", "assets", "stylesheets", "_tokens.scss")
  THEME_TOGGLE_JS = File.join(SHARED, "frontend", "theme_toggle_controller.js")
  BOTTOM_SHEET_JS = File.join(SHARED, "frontend", "bottom_sheet_controller.js")
  STIMULUS_BOOT_JS = File.join(SHARED, "frontend", "stimulus_boot.js")
  IMPORTMAP_BASELINE = File.join(SHARED, "config", "importmap_baseline.rb")
  MODAL_SCSS = File.join(SHARED, "app", "assets", "stylesheets", "_modal.scss")
  THEME_BOOTSTRAP = File.join(SHARED, "app", "views", "shared", "_theme_bootstrap.html.erb")
  ACTION_JS = File.join(SHARED, "frontend", "action_controller.js")
  ACTION_BAR = File.join(SHARED, "app", "views", "shared", "_action_bar.html.erb")
  ICON_PARTIAL = File.join(SHARED, "app", "views", "shared", "_icon.html.erb")
  ENGINE_RB = File.join(SHARED, "lib", "shared", "engine.rb")
  HOTWIRE_JS = File.join(SHARED, "frontend", "hotwire.js")
  FLEET_ROUTES = File.join(SHARED, "config", "routes", "fleet.rb")
  APPS = %w[amber brgen bsdports].freeze
  # Match real decorative depth, not "none" resets. Whitespace belongs inside
  # the lookahead so Ruby cannot backtrack past it and treat "none" as a value.
  # Flat UI also forbids blur/drop-shadow filters; semantic borders and outlines
  # carry separation and focus without a second visual language.
  FLAT_DESIGN_PATTERN = /
    box-shadow\s*:\s*(?!\s*none\b)
    | text-shadow\s*:\s*(?!\s*none\b)
    | backdrop-filter\s*:\s*(?!\s*none\b)
    | filter\s*:\s*[^;]*(?:\bblur\s*\(|\bdrop-shadow\s*\()
  /ix
  UI_STYLESHEET_EXCLUSIONS = %r{/(?:__other|vendor|builds|public/assets|node_modules)/}.freeze

  SCSS_PARAM_MAP = {
    "bg" => "bg",
    "surface" => "surface",
    "surface_elevated" => "surface-elevated",
    "text" => "text",
    "text_secondary" => "text-secondary",
    "border" => "border",
    "accent" => "accent",
    "danger" => "danger",
  }.freeze

  def test_social_tokens_match_dialect_tokens_defaults
    social = Operator::MasterDesign.tokens.fetch("social")
    scss = File.read(DIALECT_TOKENS_SCSS)
    dark_block = mixin_block(scss, "dark-tokens")

    SCSS_PARAM_MAP.each do |yaml_key, scss_param|
      next unless social.key?(yaml_key)

      expected = social.fetch(yaml_key)
      pattern = /\$#{Regexp.escape(scss_param)}:\s*(#[0-9a-f]{3,8})/i
      match = dark_block.match(pattern)
      assert match, "_dialect_tokens.scss missing default for $#{scss_param}"
      assert_equal expected.downcase, match[1].downcase, "drift: #{yaml_key}"
    end
  end

  def app_rules(app)
    styles = File.join(ROOT, app, "app", "assets", "stylesheets")
    source = File.read(File.join(styles, "application.scss"))
    Dir.glob(File.join(styles, "_#{app}_*.scss")).sort.each do |path|
      source = "#{source}\n#{File.read(path)}"
    end
    Operator::ScssRules.rules(source)
  end

  def test_bsdports_styles_load_as_ordered_feature_modules
    app = File.read(File.join(ROOT, "bsdports", "app", "assets", "stylesheets", "application.scss"))
    names = %w[
      bsdports_base
      bsdports_components
      bsdports_shared_chrome
      bsdports_tokens
      bsdports_layout
      bsdports_pages
      bsdports_states
    ]
    positions = names.map { |name| app.index(%(@include meta.load-css("#{name}");)) }

    assert positions.all?, "every BSDPorts feature module must be loaded"
    assert_equal positions.sort, positions, "BSDPorts module order is a cascade contract"
    names.each do |name|
      path = File.join(ROOT, "bsdports", "app", "assets", "stylesheets", "_#{name}.scss")
      assert File.file?(path), "missing BSDPorts feature module #{path}"
    end

    assert_includes File.read(File.join(ROOT, "bsdports", "app", "assets", "stylesheets", "_bsdports_tokens.scss")),
                    "@include x.app-root-tokens;"
    assert_includes File.read(File.join(ROOT, "bsdports", "app", "assets", "stylesheets", "_bsdports_pages.scss")),
                    "article > header"
    assert_includes app, "@include endgame.bsdports;"
    assert_operator app.lines.count, :<, 50, "application.scss should remain an entrypoint, not a second monolith"
  end

  def test_bsdports_port_header_sticks_only_when_primary_nav_fits_one_row
    pages = File.read(File.join(ROOT, "bsdports", "app", "assets", "stylesheets", "_bsdports_pages.scss"))
    mobile, wide = pages.split("@media (min-width: 640px)", 2)

    refute_nil wide, "the wide-nav breakpoint is part of the port-header layout contract"
    refute_match(/article\s*>\s*header\s*\{[^}]*position:\s*sticky/m, mobile,
                 "a wrapped mobile nav must not be covered by the sticky port header")
    assert_match(/article\s*>\s*header\s*\{[^}]*position:\s*sticky[^}]*top:\s*var\(--nav-swiper-h\)/m, wide,
                 "the port meta strip must follow the shared nav height and safe-area inset")
  end

  def test_bsdports_primary_nav_rules_target_the_rendered_landmark
    layout = File.read(File.join(ROOT, "bsdports", "app", "views", "layouts", "application.html.erb"))
    base_css = File.read(File.join(ROOT, "bsdports", "app", "assets", "stylesheets", "_bsdports_base.scss"))
    layout_css = File.read(File.join(ROOT, "bsdports", "app", "assets", "stylesheets", "_bsdports_layout.scss"))
    pages_css = File.read(File.join(ROOT, "bsdports", "app", "assets", "stylesheets", "_bsdports_pages.scss"))

    assert_match(/<nav\b[^>]*data-pwa-primary-nav/, layout,
                 "BSDports must expose the canonical primary-navigation marker")
    [layout_css, pages_css].each do |source|
      refute_match(/body\s*>\s*nav\[aria-label="Primary navigation"\]/, source,
                   "primary-nav rules must not depend on a false body-child or English-label assumption")
    end
    assert_match(/nav\[data-pwa-primary-nav\]\s*\{[^}]*min-height:\s*var\(--nav-swiper-h\)[^}]*padding-block-start:\s*calc\(0\.5rem\s*\+\s*var\(--safe-top\)\)[^}]*flex-wrap:\s*wrap/m, layout_css,
                 "nav contents must clear the device safe area without a second viewport offset")
    assert_match(/padding-block-start:\s*calc\(var\(--tap-min\)\s*\+\s*var\(--tap-min\)\s*\+\s*var\(--space-2\)\s*\+\s*1rem\s*\+\s*var\(--safe-top\)\s*\+\s*var\(--space-1\)\)/, base_css,
                 "mobile clearance must match two 44px rows, their gap, vertical nav padding, notch and one spacing step")
    assert_match(/body\s*\{[^}]*padding-block-start:\s*calc\(var\(--nav-swiper-h\)\s*\+\s*var\(--space-1\)\)/m, pages_css,
                 "wide clearance must cover one row and the top safe area")
    assert_match(/nav\[data-pwa-primary-nav\]\s+a\[aria-current="page"\]/, layout_css)
    assert_match(/nav\[data-pwa-primary-nav\]\s*\{[^}]*flex-wrap:\s*nowrap/m, pages_css)
    refute_match(/nav\[data-pwa-primary-nav\]\s*\{[^}]*transform:\s*translateY\(0\)/m, layout_css,
                 "shared chrome must retain ownership of scroll-away visibility")
  end

  def test_amber_feature_styles_are_loaded_at_their_original_boundaries
    app = File.read(File.join(ROOT, "amber", "app", "assets", "stylesheets", "application.scss"))
    styles_dir = File.join(ROOT, "amber", "app", "assets", "stylesheets")
    feature_paths = Dir.glob(File.join(styles_dir, "_amber_*.scss")).sort
    names = %w[
      amber_chrome
      amber_guest_compose
      amber_layout
      amber_wardrobe
      amber_item_forms
      amber_dashboard
      amber_dressing_room
      amber_looks
      amber_jox_logo
      amber_editorial_feed
      amber_shared_overrides
    ]
    positions = names.map { |name| app.index(%(@include meta.load-css("#{name}");)) }

    assert positions.all?, "every Amber feature module must be loaded by its entrypoint"
    assert_equal positions.sort, positions, "Amber module order is a cascade contract"
    assert_operator app.lines.count, :<, 300, "application.scss should remain an entrypoint, not another monolith"

    reachable = []
    pending = [app]
    until pending.empty?
      source = pending.shift
      source.scan(/@include meta\.load-css\(["']([^"']+)["']\)/).flatten.each do |module_name|
        candidate = File.join(styles_dir, "_#{module_name}.scss")
        next unless File.file?(candidate)
        next if reachable.include?(candidate)

        reachable << candidate
        pending << File.read(candidate)
      end
    end

    feature_paths.each do |feature|
      assert_includes reachable, feature, "#{File.basename(feature)} is not reachable from the Amber entrypoint"
      refute_empty File.read(feature), "#{File.basename(feature)} must not be empty"
    end

    expected_rules = {
      "_amber_guest_compose.scss" => ".amber-compose-box",
      "_amber_wardrobe.scss" => ".item-grid",
      "_amber_item_forms.scss" => ".form .field",
      "_amber_dashboard.scss" => ".dash-stats dl",
      "_amber_dressing_room.scss" => ".viz-rows",
      "_amber_looks.scss" => ".amber-looks",
      "_amber_jox_logo.scss" => ".jox-logo",
      "_amber_editorial_feed.scss" => ".feed-post"
    }
    expected_rules.each do |name, selector|
      assert_includes File.read(File.join(styles_dir, name)), selector, "#{name} lost its feature rule"
    end

    refute_match(%r{min-height:\s*v\s*//|font-siz\s*//}, app,
                 "entrypoint contains a stylesheet fragment split across an import")
  end

  # amber wears luxury, and stack's social light outranks a plain :root.
  #
  # `_tokens.scss` (via `@use "stack"`) emits light-tokens at
  # `[data-theme=light]` and at `:root:not([data-theme=dark])` inside
  # `prefers-color-scheme: light`. luxury-light-tokens on bare `:root` loses
  # that fight: measured 2026-08-13 on live amber, --bg was social
  # `#f7f6fa` and --accent `#5b4fc4` while --radius-card stayed luxury 14px.
  # amber's stylesheet must restate luxury in rules at those two selectors.
  def test_amber_luxury_beats_the_social_light_override
    luxury = app_rules("amber").select { |rule| rule.body.include?("luxury-light-tokens") }.map(&:selector)

    refute_empty luxury, "amber's stylesheet must include luxury-light-tokens"
    assert(luxury.any? { |selector| selector.match?(/\A:root:not\(\[data-theme=["']dark["']\]\)\z/) },
           "luxury must be restated at :root:not([data-theme=dark]) — that is the selector " \
           "stack uses for OS-light, and it outranks plain :root")
    assert(luxury.any? { |selector| selector.match?(/\A\[data-theme=["']light["']\]\z/) },
           "luxury must be restated at [data-theme=light] or the theme toggle restores social indigo")
  end

  # brgen wears the brgen_old dialect because its own stylesheet includes those
  # tokens at plain :root, outside any cascade layer. `stack_brgen` forwards
  # `_tokens.scss`, which emits the social palette inside `@layer tokens`, and
  # an un-layered declaration beats a layered one whatever the source order.
  # Moving the include into a layer, or under a narrower selector, silently
  # restores a palette this app deliberately left.
  def test_brgen_old_dialect_outranks_the_social_stack
    source = File.read(File.join(ROOT, "brgen", "app", "assets", "stylesheets", "application.scss"))
    roots = app_rules("brgen").select { |rule| rule.selector == ":root" && rule.body.include?("brgen-old-dark-tokens") }

    assert_match(/^@use "stack_brgen"/, source, "brgen/application.scss must @use stack_brgen")
    refute_empty roots, "brgen's stylesheet must include brgen-old-dark-tokens at plain :root"
    assert roots.all? { |rule| rule.parents.none? { |parent| parent.start_with?("@layer") } },
           "brgen-old sits inside a cascade layer, where the social stack's tokens can outrank it"
  end

  # The dialect section once claimed brgen was `social` / 4-8-12-16 long after
  # brgen had moved to brgen_old, and nothing caught it because no check read
  # the doc. This one does. The README states it in a sentence now (a table
  # would break the one-voice README rule), so the sentence is what is read.
  def test_the_design_doc_records_the_dialect_brgen_actually_wears
    notes = File.read(File.join(SHARED, "README.md"))
    sentence = notes.split(/(?<=\.)\s+/).find { |part| part.match?(/\bbrgen\b.*\bwear/m) }

    assert sentence, "shared/README.md must say which dialect brgen wears"
    assert_includes sentence, "brgen_old",
                    "brgen renders brgen-old-*-tokens; saying `social` here sends CSS work at the wrong palette"
  end

  def test_flat_design_pattern_rejects_effects_but_allows_resets_and_functional_filters
    prohibited = [
      "box-shadow: 0 2px 8px rgb(0 0 0 / 20%);",
      "text-shadow: 0 1px #000;",
      "backdrop-filter: blur(8px);",
      "filter: blur(2px);",
      "filter: drop-shadow(0 2px 3px #000);"
    ]
    prohibited.each do |declaration|
      assert_match FLAT_DESIGN_PATTERN, declaration, "must reject #{declaration}"
    end

    permitted = [
      "box-shadow: none;",
      "text-shadow: none;",
      "backdrop-filter: none;",
      "filter: none;",
      "filter: grayscale(1);",
      "mask-image: linear-gradient(to right, var(--surface), transparent);"
    ]
    permitted.each do |declaration|
      refute_match FLAT_DESIGN_PATTERN, declaration, "must allow #{declaration}"
    end
  end

  def test_first_party_ui_stylesheets_use_flat_visual_surfaces
    globs = [
      File.join(ROOT, "**/app/assets/stylesheets/**/*.{scss,css}"),
      File.join(SHARED, "frontend/**/*.css"),
      File.join(SHARED, "public/styles/**/*.css"),
      File.join(ROOT, "master/styles/face/**/*.css"),
      File.join(ROOT, "master/public/**/*.css"),
    ]
    paths = globs.flat_map { |glob| Dir.glob(glob) }.uniq.sort.reject do |path|
      path.match?(UI_STYLESHEET_EXCLUSIONS) || !File.file?(path)
    end
    assert paths.any?, "the visual contract must inspect first-party UI stylesheets"

    violations = paths.flat_map do |path|
      source = File.read(path, encoding: "UTF-8")
      # Blank block comments without changing line numbers; ignore standalone
      # Sass line comments so examples and explanations are not treated as UI.
      source = source.gsub(%r{/\*.*?\*/}m) { |comment| "\n" * comment.count("\n") }
      source.lines.each_with_index.filter_map do |line, index|
        next if line.lstrip.start_with?("//")
        next unless line.match?(FLAT_DESIGN_PATTERN)

        "#{path.sub("#{ROOT}/", "")}:#{index + 1}: #{line.strip}"
      end
    end

    assert_empty violations,
                 "first-party UI must stay flat: use solid surfaces, semantic borders and outlines; " \
                 "remove ornamental shadow/blur effects:\n  #{violations.join("\n  ")}"
  end

  def test_decorative_glow_controller_is_not_part_of_general_ui_chrome
    boot = File.read(STIMULUS_BOOT_JS, encoding: "UTF-8")
    refute_match(/import\s+Glow\s+from\s+["']stimulus-glow["']/, boot)
    refute_match(/\[\s*["']glow["']\s*,\s*Glow\s*\]/, boot)

    views = Dir.glob(File.join(ROOT, "**/*.{erb,html}")).reject do |path|
      path.match?(UI_STYLESHEET_EXCLUSIONS)
    end
    uses = views.filter_map do |path|
      body = File.read(path, encoding: "UTF-8")
      "#{path.sub("#{ROOT}/", "")}: data-controller glow" if body.match?(/data-controller\s*=\s*["'][^"']*\bglow\b/i)
    end
    assert_empty uses, "general UI surfaces must not opt into decorative glow controllers:\n  #{uses.join("\n  ")}"
  end

  def test_product_roots_preserve_shared_keyboard_focus_indicators
    roots = %w[amber brgen bsdports].to_h do |app|
      path = File.join(ROOT, app, "app", "assets", "stylesheets", "application.scss")
      [app, File.read(path, encoding: "UTF-8")]
    end
    roots.each do |app, source|
      assert_includes source, '@include meta.load-css("focus_ring");',
                      "#{app} must load the shared focus indicator after local styles"
    end

    brgen = roots.fetch("brgen")
    assert_includes brgen, ".post-progressive-step > h2:focus:not(:focus-visible)"
    refute_match(/\.post-progressive-step > h2:focus\s*\{\s*outline:\s*none;/m, brgen,
                 "a general focus reset must not erase the keyboard-visible state")

    ring = File.read(File.join(SHARED, "app", "assets", "stylesheets", "_focus_ring.scss"), encoding: "UTF-8")
    assert_includes ring, "outline: var(--focus-ring, 2px solid Highlight) !important;"
    assert_includes ring, "outline-offset: 2px;"
  end

  def test_theme_toggle_sets_document_element_dataset
    js = File.read(THEME_TOGGLE_JS)
    assert_includes js, "document.documentElement.dataset.theme"
  end

  def test_shared_base_locks_mobile_text_sizing
    base = File.read(File.join(ROOT, "__shared", "app", "assets", "stylesheets", "_base.scss"))
    assert_includes base, "-webkit-text-size-adjust: 100%;"
    assert_includes base, "text-size-adjust: 100%;"
  end

  def test_brgen_composer_uses_starting_style_entry
    app = File.read(File.join(ROOT, "brgen", "app", "assets", "stylesheets", "application.scss"))
    composer = File.read(File.join(ROOT, "brgen", "app", "assets", "stylesheets", "_brgen_composer.scss"))
    css = "#{app}\n#{composer}"
    refute_includes css, "composer-drop-in"
    refute_includes css, "composer-backdrop-in"
    assert_includes css, "@starting-style"
    assert_includes css, ".composer[open]::backdrop"
  end

  def test_brgen_feature_styles_are_loaded_at_their_original_boundaries
    app = File.read(File.join(ROOT, "brgen", "app", "assets", "stylesheets", "application.scss"))
    feature_paths = Dir.glob(File.join(ROOT, "brgen", "app", "assets", "stylesheets", "_brgen_*.scss")).sort

    refute_empty feature_paths, "Brgen must have feature-owned stylesheet modules"
    reachable = []
    pending = [app]
    until pending.empty?
      source = pending.shift
      source.scan(/@include meta\.load-css\(["']([^"']+)["']\)/).flatten.each do |module_name|
        candidate = File.join(ROOT, "brgen", "app", "assets", "stylesheets", "_#{module_name}.scss")
        next unless File.file?(candidate)
        next if reachable.include?(candidate)

        reachable << candidate
        pending << File.read(candidate)
      end
    end

    feature_paths.each do |path|
      module_name = File.basename(path).delete_prefix("_").delete_suffix(".scss")
      assert_includes reachable, path, "#{module_name} is not reachable from the host stylesheet"
      refute_empty File.read(path), "#{module_name} is empty"
    end

    expected_rules = {
      "_brgen_marketplace.scss" => ".deal-card",
      "_brgen_vertical_surfaces.scss" => ".listing-buy-bar-cta",
      "_brgen_shared_city_campaigns.scss" => ".store-promo-art-cta",
      "_brgen_messenger.scss" => ".messenger-artifact-pane",
      "_brgen_composer.scss" => ".composer[open]::backdrop",
      "_brgen_feed_posts.scss" => ".feed-action",
      "_brgen_nearby_channels.scss" => ".nearby-alert",
      "_brgen_share_media.scss" => ".media-actions",
      "_brgen_dating.scss" => ".swipe-card",
      "_brgen_vertical_shell.scss" => "body[class*=\"vertical-\"] .feed-header",
      "_brgen_city_surfaces.scss" => ".profile-header"
    }
    expected_rules.each do |name, selector|
      path = File.join(ROOT, "brgen", "app", "assets", "stylesheets", name)
      assert_includes feature_paths, path
      assert_includes File.read(path), selector, "#{name} lost its representative feature rule"
    end

    [".deal-card", ".listing-buy-bar-cta", ".store-promo-art-cta", ".messenger-artifact-pane",
     ".composer[open]::backdrop", ".feed-action", ".nearby-alert", ".media-actions",
     ".swipe-card", ".profile-header"].each do |selector|
      refute Operator::ScssRules.matching(app, /#{Regexp.escape(selector)}/).any?,
             "#{selector} should live in a feature partial, not application.scss"
    end
  end

  def test_brgen_marketplace_header_uses_mobile_first_breakpoints
    path = File.join(ROOT, "brgen", "app", "assets", "stylesheets", "_brgen_shared_marketplace_header.scss")
    source = File.read(path)

    refute_match(/@media\s*\(\s*max-width\b/, source,
                 "compact storefront rules are the base, not a max-width override")
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
    assert_match(/body\[data-surface="luxury"\] \.luxury-title\s*\{[^}]*max-inline-size:\s*none;[^}]*font-size:\s*clamp\(2\.4rem, 12vw, 4rem\);/m, amber_mobile)
    assert_match(/body\[data-surface="luxury"\] main#main-content\s*\{[^}]*padding-inline:\s*0;[^}]*padding-block-end:\s*calc\(var\(--space-12\) \+ var\(--safe-bottom\)\);/m, amber_wide)
    assert_match(/body\[data-surface="luxury"\] \.luxury-title\s*\{[^}]*max-inline-size:\s*12ch;[^}]*font-size:\s*clamp\(2\.4rem, 5vw, 5rem\);/m, amber_wide)

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

  def test_newsletter_capture_is_mobile_first
    source = File.read(File.join(ROOT, "__shared", "app", "assets", "stylesheets", "_newsletter_capture.scss"))
    mobile = source.split("@media (min-width: 640px)", 2).first
    wide = source.split("@media (min-width: 640px)", 2).last

    refute_match(/@media\s*\(\s*max-width\b/, source)
    assert_match(/\.newsletter-capture\s*\{[^}]*inline-size:\s*calc\(100vw - 1rem\);/m, mobile)
    assert_match(/\.newsletter-capture-art\s*\{[^}]*min-block-size:\s*8rem;/m, mobile)
    assert_match(/\.newsletter-capture-copy\s*\{[^}]*padding:\s*var\(--space-4\);/m, mobile)
    assert_match(/\.newsletter-capture\s*\{[^}]*inline-size:\s*min\(42rem, calc\(100vw - 2rem\)\);/m, wide)
    assert_match(/\.newsletter-capture-art\s*\{[^}]*min-block-size:\s*11rem;/m, wide)
    assert_match(/\.newsletter-capture-copy\s*\{[^}]*padding:\s*var\(--space-5\);/m, wide)
  end

  def test_post_voting_compact_gap_is_mobile_first
    source = File.read(File.join(ROOT, "__shared", "app", "assets", "stylesheets", "_post_voting.scss"))
    mobile = source.split("@media (min-width: 480px)", 2).first
    wide = source.split("@media (min-width: 480px)", 2).last

    refute_match(/@media\s*\(\s*max-width\b/, source)
    assert_match(/\.post-reading-layout\s*\{[^}]*gap:\s*var\(--space-2\);/m, mobile)
    assert_match(/\.post-reading-layout\s*\{[^}]*gap:\s*var\(--space-3\);/m, wide)
  end

  def test_brgen_marketplace_badge_offsets_are_valid_css
    path = File.join(ROOT, "brgen", "app", "assets", "stylesheets", "_brgen_marketplace.scss")
    source = File.read(path)

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
    source = File.read(File.join(ROOT, "brgen", "app", "assets", "stylesheets", "application.scss"))
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

  # --tap-min is 44px. A min-height/min-width written as the literal is the same
  # paint as the token and is how the floor drifted: half the family pointed at
  # the token and half restated the number. Use-sites must read the token;
  # definitions (`--tap-min: 44px`) and already-tokenised fallbacks stay.
  TAP_FLOOR_LITERAL = /(?<![\w-])(min-height|min-width|min-inline-size|min-block-size)\s*:\s*44px\b/
  TAP_FLOOR_SKIP = %r{/(builds|vendor|node_modules|public/assets)/}

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

  def mixin_block(scss, name)
    start = scss.index("@mixin #{name}")
    assert start, "missing @mixin #{name}"
    depth = 0
    i = start
    while i < scss.length
      depth += 1 if scss[i] == "{"
      if scss[i] == "}"
        depth -= 1
        return scss[start..i] if depth.zero? && i > start
      end
      i += 1
    end
    flunk "unclosed mixin #{name}"
  end

  def compiled_css_path(app)
    primary = File.join(ROOT, app, "app", "assets", "builds", "application.css")
    return primary if File.file?(primary)

    File.join(ROOT, app, "app", "assets", "builds", "app.css")
  end

  def tap_floor_stylesheets
    rails = Dir.glob(File.join(ROOT, "{*,#{EngineRoots::GLOB}}/app/assets/stylesheets/**/*.{scss,css}")) +
            Dir.glob(File.join(ROOT, "__shared/app/assets/stylesheets/**/*.{scss,css}")) +
            Dir.glob(File.join(ROOT, "__shared/frontend/**/*.css"))
    face = File.expand_path("../RAILS/master/public/face.css", ROOT)
    (rails + [face]).uniq.reject { |path| path.match?(TAP_FLOOR_SKIP) || !File.file?(path) }
  end
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
