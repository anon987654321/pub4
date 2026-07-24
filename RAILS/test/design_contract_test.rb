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
  # Match real elevation, not "box-shadow: none" flat overrides (same exception
  # as RAILS/gates/lib/gate_autofix.rb and css constitution detection).
  FLAT_DESIGN_PATTERN = /
    box-shadow\s*:\s*(?!none\b)[^;]+
    | text-shadow\s*:\s*(?!none\b)[^;]+
    | backdrop-filter\s*:\s*(?!none\b)[^;]+
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

    assert_includes js, 'static targets = ["sheet", "backdrop"]'
    assert_includes js, "pointerDown(event)"
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
    assert_includes partial, 'data-controller="action"'
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
end
