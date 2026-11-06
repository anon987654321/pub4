# frozen_string_literal: true

# Recovered / adapted from recover/x-parity-stack (325e3edac).
# Asserts contracts against current main paths (not the obsolete pub4_* renames).
require "yaml"
require "minitest/autorun"
require_relative "engine_roots"
require_relative "support/stylesheet_modules"
require_relative "../../MASTER/tools/master_design"
require_relative "../../MASTER/tools/scss"
require_relative "support/design_contract_sources"

class DesignContractTest < Minitest::Test
  include DesignContractSources

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

def test_bsdports_styles_load_as_ordered_feature_modules
  # One stylesheet per app (operator, 2026-10-28): the former partials are
  # module banners, and their order is still the cascade contract.
  names = stylesheet_module_names("bsdports")

  assert_equal %w[
    bsdports_base
    bsdports_components
    bsdports_shared_chrome
    bsdports_tokens
    bsdports_layout
    bsdports_pages
    bsdports_states
  ], names, "BSDPorts module order is a cascade contract"

  assert_includes stylesheet_module("bsdports", "bsdports_tokens"), "@include x.app-root-tokens;"
  assert_includes stylesheet_module("bsdports", "bsdports_pages"), "article > header"
  assert_includes application_scss("bsdports"), "@include endgame.bsdports;"
end


def test_bsdports_port_header_sticks_only_when_primary_nav_fits_one_row
  pages = stylesheet_module("bsdports", "bsdports_pages")
  mobile, wide = pages.split("@media (min-width: 640px)", 2)

  refute_nil wide, "the wide-nav breakpoint is part of the port-header layout contract"
  refute_match(/article\s*>\s*header\s*\{[^}]*position:\s*sticky/m, mobile,
               "a wrapped mobile nav must not be covered by the sticky port header")
  assert_match(/article\s*>\s*header\s*\{[^}]*position:\s*sticky[^}]*top:\s*var\(--nav-swiper-h\)/m, wide,
               "the port meta strip must follow the shared nav height and safe-area inset")
end


def test_bsdports_primary_nav_rules_target_the_rendered_landmark
  layout = File.read(File.join(ROOT, "bsdports", "app", "views", "layouts", "application.html.erb"))
  base_css = stylesheet_module("bsdports", "bsdports_base")
  layout_css = stylesheet_module("bsdports", "bsdports_layout")
  pages_css = stylesheet_module("bsdports", "bsdports_pages")


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
    assert_match(/nav\[data-pwa-primary-nav\]\s+a\[aria-current\]/, layout_css)
    assert_match(/nav\[data-pwa-primary-nav\]\s*\{[^}]*flex-wrap:\s*nowrap/m, pages_css)
    refute_match(/nav\[data-pwa-primary-nav\]\s*\{[^}]*transform:\s*translateY\(0\)/m, layout_css,
                 "shared chrome must retain ownership of scroll-away visibility")
  end

# One stylesheet per app (operator, 2026-10-28): the former feature partials
# live between module banners and their order is still the cascade contract
# the meta.load-css calls used to be.
def test_amber_feature_styles_are_loaded_at_their_original_boundaries
  names = stylesheet_module_names("amber")

  assert_equal %w[
    commerce_polish
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
  ], names, "Amber module order is a cascade contract"

  # Pairs, not a hash: a module can own more than one pinned rule.
  expected_rules = [
    ["amber_guest_compose", ".amber-compose-box"],
    ["amber_wardrobe", ".item-grid"],
    ["amber_item_forms", ".form .field"],
    ["amber_dashboard", ".dash-stats dl"],
    ["amber_dressing_room", ".viz-rows"],
    ["amber_looks", ".amber-looks"],
    ["amber_jox_logo", ".jox-logo"],
    ["amber_editorial_feed", ".feed-post"]
  ]
  expected_rules.each do |name, selector|
    assert_includes stylesheet_module("amber", name), selector, "#{name} lost its feature rule"
  end

  refute_match(%r{min-height:\s*v\s*//|font-siz\s*//}, application_scss("amber"),
               "the sheet contains a stylesheet fragment split across an import")
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
  source = stylesheet_source("brgen")
  roots = app_rules("brgen").select { |rule| rule.selector == ":root" && rule.body.include?("brgen-old-dark-tokens") }

  assert_includes(source, '@include meta.load-css("stack_brgen");',
                  "brgen/application.scss must load stack_brgen at the top level, outside any @layer")

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
      File.join(ROOT, "../MASTER/web/styles/face/**/*.css"),
      File.join(ROOT, "../MASTER/web/public/**/*.css"),
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
    roots = %w[amber brgen bsdports].to_h { |app| [app, stylesheet_source(app)] }
    roots.each do |app, source|
      assert_includes source, '@include meta.load-css("focus_ring");',
                      "#{app} must load the shared focus indicator after local styles"
    end

    brgen = roots.fetch("brgen")
    assert_includes brgen, ".post-progressive-step > h2:focus:not(:focus-visible)"
    refute_match(/\.post-progressive-step > h2:focus\s*\{\s*outline:\s*none;/m, brgen,
                 "a general focus reset must not erase the keyboard-visible state")

    ring = File.read(File.join(SHARED, "app", "assets", "stylesheets", "_focus_ring.scss"), encoding: "UTF-8")
    assert_includes ring, "outline: var(--focus-ring, 2px solid Highlight);"
    # No component clears the outline, so the ring needs no !important list (shared-001).
    refute_match(/!important\s*;/, ring)
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
end
