# frozen_string_literal: true

# Recovered / adapted from recover/x-parity-stack (325e3edac).
# Asserts contracts against current main paths (not the obsolete pub4_* renames).
require "yaml"
require "minitest/autorun"

class DesignContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SHARED = File.join(ROOT, "shared")
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
  # Match real elevation, not "box-shadow: none" flat overrides.
  # Lookahead must include optional whitespace so `\s*` cannot backtrack past
  # "none" (Ruby would otherwise match "box-shadow:" + " none ..." as a hit).
  FLAT_DESIGN_PATTERN = /
    box-shadow\s*:\s*(?!\s*none\b)
    | text-shadow\s*:\s*(?!\s*none\b)
    | backdrop-filter\s*:\s*(?!\s*none\b)
  /ix
  DIALECT_PARTIALS = %w[_dialect_tokens.scss _shell.scss _shell_widgets.scss _responsive.scss _modal.scss].freeze

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
    social = YAML.safe_load_file(TOKENS_YML).fetch("social")
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

  # brgen wears the brgen_old dialect, and it wins on source order alone.
  #
  # `stack_brgen` forwards `_tokens.scss`, which emits the social indigo palette
  # at plain `:root`. `_root.scss` emits brgen-old at plain `:root` too — same
  # specificity — so the only thing making brgen grayscale rather than indigo is
  # that `@use "_root"` comes *after* `@use "stack_brgen"` in application.scss.
  # Reordering those lines, or moving _root into the stack, silently restores a
  # palette this app deliberately left, with nothing failing to say so.
  #
  # Verified 2026-08-10 against brgen/app/assets/builds/application.css: two
  # `:root` blocks, the second `--bg: #000000` / `--text: #e0e0e0` /
  # `--accent: #f2f2f2` / `--radius-card: 8px`.
  # amber wears luxury, and stack's social light outranks a plain :root.
  #
  # `_tokens.scss` (via `@use "stack"`) emits light-tokens at
  # `[data-theme=light]` and at `:root:not([data-theme=dark])` inside
  # `prefers-color-scheme: light`. luxury-light-tokens on bare `:root` loses
  # that fight: measured 2026-08-13 on amber.brgen.no, --bg was social
  # `#f7f6fa` and --accent `#5b4fc4` while --radius-card stayed luxury 14px.
  # `_variables.scss` must restate luxury at those two selectors.
  def test_amber_luxury_beats_the_social_light_override
    variables = File.read(File.join(ROOT, "amber", "app", "assets", "stylesheets", "_variables.scss"))

    assert_includes variables, "luxury-light-tokens",
                    "amber/_variables.scss must include luxury-light-tokens"
    assert_match(/:root:not\(\[data-theme=["']dark["']\]\)/, variables,
                 "luxury must be restated at :root:not([data-theme=dark]) — that is the selector " \
                 "stack uses for OS-light, and it outranks plain :root")
    assert_match(/\[data-theme=["']light["']\]/, variables,
                 "luxury must be restated at [data-theme=light] or the theme toggle restores social indigo")
  end

  def test_brgen_old_dialect_is_emitted_after_the_social_stack
    app_scss = File.read(File.join(ROOT, "brgen", "app", "assets", "stylesheets", "application.scss"))
    uses = app_scss.scan(/^@use\s+"([^"]+)"/).flatten

    stack = uses.index { |name| name == "stack_brgen" }
    root  = uses.index { |name| name.delete_prefix("_") == "root" }

    assert stack, "brgen/application.scss must @use stack_brgen"
    assert root, "brgen/application.scss must @use _root (the brgen_old dialect)"
    assert_operator root, :>, stack,
                    "_root must come after stack_brgen or brgen renders the social indigo palette " \
                    "instead of its own grayscale one — same specificity, source order decides"
  end

  # The dialect table in WIRING_NOTES claimed brgen was `social` / 4-8-12-16 long
  # after brgen had moved to brgen_old, and nothing caught it because no check
  # read the doc. This one does.
  def test_wiring_notes_records_the_dialect_brgen_actually_wears
    notes = File.read(File.join(SHARED, "WIRING_NOTES.md"))
    worn = notes[/\*\*Worn at `:root`.*?\n\n/m]

    assert worn, "WIRING_NOTES must keep a 'Worn at :root' table — declared mixins are not worn dialects"
    brgen_row = worn.lines.find { |line| line.start_with?("| brgen") }
    assert brgen_row, "the worn table must have a brgen row"
    assert_includes brgen_row, "brgen_old",
                    "brgen renders brgen-old-*-tokens; saying `social` here sends CSS work at the wrong palette"
  end

  def test_no_shadow_blur_in_x_partials
    DIALECT_PARTIALS.each do |name|
      path = File.join(SHARED, "app", "assets", "stylesheets", name)
      body = File.read(path)
      refute_match(FLAT_DESIGN_PATTERN, body, "#{path} must stay flat (no shadow/blur)")
    end
  end

  def test_theme_toggle_sets_document_element_dataset
    js = File.read(THEME_TOGGLE_JS)
    assert_includes js, "document.documentElement.dataset.theme"
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

  def test_action_controller_posts_body
    js = File.read(ACTION_JS)
    assert_includes js, "URLSearchParams"
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
    rails = Dir.glob(File.join(ROOT, "*/app/assets/stylesheets/**/*.{scss,css}")) +
            Dir.glob(File.join(ROOT, "*/engines/*/app/assets/stylesheets/**/*.{scss,css}")) +
            Dir.glob(File.join(ROOT, "shared/app/assets/stylesheets/**/*.{scss,css}")) +
            Dir.glob(File.join(ROOT, "shared/frontend/**/*.css"))
    face = File.expand_path("../MASTER/web/public/face.css", ROOT)
    (rails + [face]).uniq.reject { |path| path.match?(TAP_FLOOR_SKIP) || !File.file?(path) }
  end
end
