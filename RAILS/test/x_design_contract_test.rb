# frozen_string_literal: true

require "yaml"
require "minitest/autorun"

class XDesignContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SHARED = File.join(ROOT, "shared")
  X_BASE = File.join(SHARED, "app", "assets", "stylesheets", "_x_base.scss")
  TOKENS_YML = File.join(SHARED, "design_tokens.yml")
  TOKENS_CSS = File.join(SHARED, "public", "styles", "tokens.css")
  BRGEN_ROOT = File.join(ROOT, "brgen", "app", "assets", "stylesheets", "_root.scss")
  AMBER_VARS = File.join(ROOT, "amber", "app", "assets", "stylesheets", "_variables.scss")
  BRGEN_LAYOUT = File.join(ROOT, "brgen", "app", "views", "layouts", "application.html.erb")
  X_SHELL_PARTIAL = File.join(SHARED, "app", "views", "shared", "_x_shell.html.erb")
  AMBER_LAYOUT = File.join(ROOT, "amber", "app", "views", "layouts", "application.html.erb")
  BSDPORTS_LAYOUT = File.join(ROOT, "bsdports", "app", "views", "layouts", "application.html.erb")
  TOKENS_SCSS = File.join(SHARED, "app", "assets", "stylesheets", "_tokens.scss")
  THEME_TOGGLE_JS = File.join(SHARED, "frontend", "pub4_theme_toggle_controller.js")
  BOTTOM_SHEET_JS = File.join(SHARED, "frontend", "bottom_sheet_controller.js")
  STIMULUS_BOOT_JS = File.join(SHARED, "frontend", "pub4_stimulus_boot.js")
  IMPORTMAP_BASELINE = File.join(SHARED, "config", "importmap_baseline.rb")
  BRGEN_BOTTOM_SHEET_JS = File.join(ROOT, "brgen", "app", "javascript", "controllers", "bottom_sheet_controller.js")
  BRGEN_APPLICATION_SCSS = File.join(ROOT, "brgen", "app", "assets", "stylesheets", "application.scss")
  X_MODAL_SCSS = File.join(SHARED, "app", "assets", "stylesheets", "_x_modal.scss")
  THEME_BOOTSTRAP_PARTIAL = File.join(SHARED, "app", "views", "shared", "_theme_bootstrap.html.erb")
  X_ACTION_JS = File.join(SHARED, "frontend", "pub4_x_action_controller.js")
  X_ACTION_BAR = File.join(SHARED, "app", "views", "shared", "_x_action_bar.html.erb")
  REACTION_BAR = File.join(SHARED, "app", "views", "shared", "_reaction_bar.html.erb")
  ENGINE_RB = File.join(SHARED, "lib", "shared", "engine.rb")
  APPS = %w[amber brgen bsdports].freeze

  SCSS_PARAM_MAP = {
    "x_bg" => "bg",
    "x_surface" => "surface",
    "x_surface_elevated" => "surface-elevated",
    "x_search_bg" => "search-bg",
    "x_text" => "text",
    "x_text_secondary" => "text-secondary",
    "x_border" => "border",
    "x_accent" => "accent",
    "x_accent_hover" => "accent-hover",
    "x_danger" => "danger",
  }.freeze

  SCSS_LITERAL_MAP = {
    "x_font_size" => /--x-font-size:\s*([^;]+);/,
    "x_line_height" => /--x-line-height:\s*([^;]+);/,
    "x_radius_pill" => /--x-radius-pill:\s*([^;]+);/,
    "x_radius_card" => /--x-radius-card:\s*([^;]+);/,
    "x_sidebar" => /--x-sidebar:\s*([^;]+);/,
    "x_feed_max" => /--x-feed-max:\s*([^;]+);/,
    "x_widgets" => /--x-widgets:\s*([^;]+);/,
    "x_layout_max" => /--x-layout-max:\s*([^;]+);/,
  }.freeze

  SEMANTIC_ALIAS_DECLARATIONS = [
    "--x-success: var(--color-success);",
    "--x-warning: var(--color-warning);",
    "--x-like-active: var(--x-accent);",
    "--x-repost-active: var(--color-success);",
  ].freeze

  TOKENS_CSS_LAYOUT_VARS = %w[
    --x-sidebar
    --x-feed-max
    --x-widgets
    --x-layout-max
    --x-accent-hover
  ].freeze

  SYSTEM_UI_FONT = '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif'.freeze
  FLAT_DESIGN_PATTERN = /box-shadow|text-shadow|backdrop-filter/i
  CYCLIC_X_DANGER_PATTERN = /--x-danger:\s*var\(--x-danger\)/

  def test_social_tokens_match_x_base_defaults
    social = YAML.safe_load_file(TOKENS_YML).fetch("social")
    scss = File.read(X_BASE)
    dark_block = mixin_block(scss, "x-dark-tokens")

    SCSS_PARAM_MAP.each do |yaml_key, scss_param|
      expected = social.fetch(yaml_key)
      pattern = /\$#{Regexp.escape(scss_param)}:\s*(#[0-9a-f]{3,8})/i
      match = dark_block.match(pattern)
      assert match, "_x_base.scss missing default for $#{scss_param}"
      assert_equal expected.downcase, match[1].downcase, "drift: #{yaml_key}"
    end

    SCSS_LITERAL_MAP.each do |yaml_key, pattern|
      expected = social.fetch(yaml_key).strip
      match = dark_block.match(pattern)
      assert match, "_x_base.scss missing literal for #{yaml_key}"
      assert_equal expected, match[1].strip, "drift: #{yaml_key}"
    end

    assert_includes dark_block, "--x-font: #{SYSTEM_UI_FONT};"
    assert_equal social.fetch("x_font"), SYSTEM_UI_FONT
  end

  def test_light_tokens_match_x_base_defaults
    light = YAML.safe_load_file(TOKENS_YML).fetch("light")
    scss = File.read(X_BASE)
    light_block = mixin_block(scss, "x-light-tokens")

    SCSS_PARAM_MAP.each do |yaml_key, scss_param|
      expected = light.fetch(yaml_key)
      pattern = /\$#{Regexp.escape(scss_param)}:\s*(#[0-9a-f]{3,8})/i
      match = light_block.match(pattern)
      assert match, "_x_base.scss missing light default for $#{scss_param}"
      assert_equal expected.downcase, match[1].downcase, "light drift: #{yaml_key}"
    end
  end

  def test_brgen_does_not_override_x_accent
    root_scss = File.read(BRGEN_ROOT)
    refute_includes root_scss, "--x-accent: #1d55f0"
    refute_includes root_scss, "--x-accent-hover: #1a4dd8"
  end

  def test_tokens_scss_defines_semantic_status_aliases
    tokens = File.read(File.join(SHARED, "app", "assets", "stylesheets", "_tokens.scss"))
    x_base = File.read(X_BASE)
    assert_includes tokens, "@include x.x-semantic-status-tokens;"
    SEMANTIC_ALIAS_DECLARATIONS.each do |declaration|
      assert_includes x_base, declaration
    end
    refute_includes x_base, "--x-danger: var(--x-danger);"
    refute_includes File.read(TOKENS_YML), "x_like_active:"
  end

  def test_tokens_css_syncs_system_ui_font_layout_and_semantic_aliases
    body = File.read(TOKENS_CSS)
    refute_includes body, '--x-font: "JetBrainsMono Nerd Font"'
    assert_includes body, "--x-font: #{SYSTEM_UI_FONT};"
    TOKENS_CSS_LAYOUT_VARS.each do |token|
      assert_includes body, token, "tokens.css missing #{token}"
    end
    SEMANTIC_ALIAS_DECLARATIONS.each do |declaration|
      assert_includes body, declaration, "tokens.css missing #{declaration}"
    end
  end

  def test_compiled_css_has_no_cyclic_x_danger
    APPS.each do |app|
      css = compiled_css_path(app)
      next unless File.file?(css)

      refute_match(CYCLIC_X_DANGER_PATTERN, File.read(css), "#{app} #{File.basename(css)} has cyclic --x-danger")
    end
  end

  def test_no_shadow_blur_in_x_partials
    Dir[File.join(SHARED, "app", "assets", "stylesheets", "_x_*.scss")].each do |path|
      body = File.read(path)
      refute_match(FLAT_DESIGN_PATTERN, body, "#{path} must stay flat (no shadow/blur)")
    end
  end

  def test_bsdports_layout_links_app_stylesheet
    layout = File.read(BSDPORTS_LAYOUT)
    assert_match(/stylesheet_link_tag\s+:app/, layout)
    refute_match(/stylesheet_link_tag\s+:application/, layout)
    refute_match(/stylesheet_link_tag\s+["']application["']/, layout)
  end

  def test_theme_toggle_controller_sets_document_element_dataset
    js = File.read(THEME_TOGGLE_JS)
    assert_includes js, "document.documentElement.dataset.theme"
  end

  def test_bottom_sheet_controller_promoted_to_shared
    js = File.read(BOTTOM_SHEET_JS)
    boot = File.read(STIMULUS_BOOT_JS)
    importmap = File.read(IMPORTMAP_BASELINE)
    modal = File.read(X_MODAL_SCSS)
    brgen_scss = File.read(BRGEN_APPLICATION_SCSS)

    assert_includes js, 'static targets = ["sheet", "backdrop"]'
    assert_includes js, "pointerDown(event)"
    assert_includes boot, 'import BottomSheet from "pub4/bottom_sheet"'
    assert_includes boot, 'application.register("bottom-sheet", BottomSheet)'
    assert_includes importmap, 'pin "pub4/bottom_sheet", to: "bottom_sheet_controller.js"'
    refute File.file?(BRGEN_BOTTOM_SHEET_JS), "brgen must not keep a local bottom_sheet_controller.js"
    refute_includes brgen_scss, '@use "_mobile"'
    assert_includes modal, ".mobile-sheet-backdrop"
    assert_includes modal, ".dialog"
  end

  def test_theme_bootstrap_partial_sets_dataset_before_paint
    partial = File.read(THEME_BOOTSTRAP_PARTIAL)
    assert_includes partial, "document.documentElement.dataset.theme"
    assert_includes partial, "localStorage.getItem"
    assert_includes partial, "content_security_policy_nonce"
  end

  def test_layouts_bootstrap_theme_before_stylesheets
    [BRGEN_LAYOUT, AMBER_LAYOUT].each do |layout_path|
      layout = File.read(layout_path)
      assert_includes layout, "shared/theme_bootstrap"
      bootstrap_idx = layout.index("theme_bootstrap")
      stylesheet_idx = layout.index("stylesheet_link_tag")
      assert bootstrap_idx, "#{layout_path} missing theme bootstrap"
      assert stylesheet_idx, "#{layout_path} missing stylesheet link"
      assert bootstrap_idx < stylesheet_idx, "#{layout_path} must bootstrap theme before stylesheet"
    end
  end

  def test_tokens_scss_uses_html_data_theme_selectors
    tokens = File.read(TOKENS_SCSS)
    assert_includes tokens, 'html[data-theme="dark"]'
    assert_includes tokens, 'html[data-theme="light"]'
    assert_includes tokens, "html:not([data-theme])"
    refute_includes tokens, ':root:not([data-theme="dark"])'
  end

  def test_brgen_and_amber_scss_no_checkbox_sibling_hack
    [BRGEN_ROOT, AMBER_VARS].each do |path|
      body = File.read(path)
      refute_includes body, "#dark-toggle:checked", "#{path} still uses checkbox-sibling theme hack"
      assert_includes body, 'html[data-theme="dark"]', "#{path} missing html[data-theme=\"dark\"]"
      assert_includes body, 'html[data-theme="light"]', "#{path} missing html[data-theme=\"light\"]"
    end
  end

  def test_brgen_compiled_css_uses_html_data_theme_selectors
    css_path = File.join(ROOT, "brgen", "app", "assets", "builds", "application.css")
    css = File.read(css_path)
    assert_includes css, "html[data-theme=dark]"
    assert_includes css, "html[data-theme=light]"
    assert_includes css, "html:not([data-theme])"
    refute_includes css, "#dark-toggle:checked"
  end

  def test_x_action_controller_posts_reaction_body
    js = File.read(X_ACTION_JS)
    assert_includes js, "URLSearchParams"
    assert_includes js, "target_gid: this.targetGidValue"
    assert_includes js, "kind: this.kindValue"
    assert_includes js, "application/x-www-form-urlencoded"
  end

  def test_shared_x_ui_helper_initializer_registered
    engine = File.read(ENGINE_RB)
    assert_includes engine, 'initializer "shared.x_ui_helper"'
    assert_includes engine, "helper Shared::XUiHelper"
  end

  def test_x_action_partials_single_count_target_per_scope
    [X_ACTION_BAR, REACTION_BAR].each do |path|
      body = File.read(path)
      x_action_blocks = body.split(/(?=data-controller="x-action")/).drop(1)
      refute_empty x_action_blocks, "#{path} missing x-action buttons"

      x_action_blocks.each do |block|
        button_block = block[/\A[\s\S]*?<\/button>/m]
        assert button_block, "#{path} malformed x-action button block"
        count_targets = button_block.scan(/data-x-action-target="count"/)
        assert_equal 1, count_targets.size, "#{path} must have exactly one count target per x-action button"
      end
    end
  end

  def test_x_action_bar_share_uses_clipboard_source_target
    partial = File.read(X_ACTION_BAR)
    assert_includes partial, 'data-clipboard-target="source"'
    refute_includes partial, "data-clipboard-source-value"
  end

  def test_x_action_bar_hides_zero_like_count
    partial = File.read(X_ACTION_BAR)
    assert_includes partial, 'like_count.positive? ? like_count : ""'
  end

  def test_bsdports_layout_includes_x_shell_markers
    layout = File.read(BSDPORTS_LAYOUT)
    shell = File.read(X_SHELL_PARTIAL)

    assert_includes layout, 'render "shared/x_shell"'
    assert_includes layout, 'render "shared/x_tab_bar"'
    assert_includes layout, 'render "shared/x_search_widget"'
    assert_includes shell, "data-x-shell"
    assert_includes shell, "yield :before_main"
    assert_includes shell, "yield :main"
    assert_includes shell, "yield :widgets"
    assert_includes shell, "if local_assigns[:sidebar_items]"
    assert_includes shell, 'render "shared/x_sidebar_nav"'

    refute_includes layout, 'class="nav-visible"'
    refute_includes layout, 'class="logo"'
    refute_includes shell, 'class="tab-bar"'
  end

  def test_brgen_layout_includes_x_shell_markers
    layout = File.read(BRGEN_LAYOUT)
    shell = File.read(X_SHELL_PARTIAL)

    assert_includes layout, 'render "shared/x_shell"'
    assert_includes layout, 'render "shared/x_feed_header"'
    assert_includes layout, 'render "shared/x_search_widget"'
    assert_includes layout, 'render "shared/x_tab_bar"'
    assert_includes shell, "data-x-shell"
    assert_includes shell, "yield :before_main"
    assert_includes shell, "yield :main"
    assert_includes shell, "yield :widgets"

    # Brgen layout inventory stays outside _x_shell.
    assert_includes layout, 'render "shared/nav_swiper"'
    assert_includes layout, 'id="cityCarousel"'
    assert_includes layout, "pull-to-refresh"
    assert_includes layout, "nav-affordance"
    assert_includes layout, "compose-fab"
    assert_includes layout, "mobile-sheet"
    assert_includes layout, 'data-controller="bottom-sheet"'
    assert_includes layout, "particle_kernel"
    assert_includes layout, "yield :widgets"
    refute_includes shell, "nav_swiper"
    refute_includes shell, 'id="cityCarousel"'
    refute_match(/data-controller="pull-to-refresh"/, shell)
    refute_includes shell, 'class="tab-bar"'
    refute_includes shell, 'class="compose-fab"'
    refute_includes shell, 'class="mobile-sheet"'
    assert_includes shell, "if local_assigns[:sidebar_items]"
    assert_includes shell, 'render "shared/x_sidebar_nav"'
    sidebar_nav = File.read(File.join(SHARED, "app", "views", "shared", "_x_sidebar_nav.html.erb"))
    assert_includes sidebar_nav, "local_assigns[:items].presence || sidebar_nav_items"
  end

  def test_amber_layout_includes_x_shell_markers
    layout = File.read(AMBER_LAYOUT)
    shell = File.read(X_SHELL_PARTIAL)

    assert_includes layout, 'render "shared/x_shell"'
    assert_includes layout, 'render "shared/x_tab_bar"'
    assert_includes layout, "body_surface_classes"
    assert_includes layout, "app-shell"
    assert_includes shell, "data-x-shell"
    assert_includes shell, "yield :main"
    assert_includes shell, "yield :widgets"
    assert_includes shell, "yield :sidebar_compose"
    assert_includes shell, 'render "shared/x_sidebar_nav"'

    # Amber layout inventory stays outside _x_shell.
    assert_includes layout, "amber-logo-banner"
    assert_includes layout, "wardrobe_showcase"
    assert_includes layout, "compose-fab"
    refute_includes shell, "amber-logo-banner"
    refute_includes shell, "wardrobe_showcase"
    refute_includes shell, 'class="compose-fab"'
    refute_includes shell, 'class="tab-bar"'
    refute_includes layout, 'data-controller="bottom-sheet"'
    assert_includes layout, "more_button: false"

    showcase_idx = layout.index("wardrobe_showcase")
    shell_idx = layout.index('render "shared/x_shell"')
    assert showcase_idx, "amber layout missing wardrobe_showcase"
    assert shell_idx, "amber layout missing x_shell render"
    assert showcase_idx < shell_idx, "wardrobe showcase must render above shared/_x_shell"
  end

  def test_amber_luxury_css_scoped_to_product_luxury
    items_luxury = File.read(File.join(ROOT, "amber", "app", "assets", "stylesheets", "_items_luxury.scss"))
    guest_showcase = File.read(File.join(ROOT, "amber", "app", "assets", "stylesheets", "_guest_showcase.scss"))
    tokens = File.read(TOKENS_SCSS)
    layout = File.read(AMBER_LAYOUT)
    helper = File.read(File.join(ROOT, "amber", "app", "helpers", "application_helper.rb"))

    assert_includes items_luxury, "body.product-luxury"
    assert_includes guest_showcase, "body.product-luxury"
    refute_includes tokens, "--luxury-bg:"
    assert_includes layout, "if product_luxury_surface?"
    luxury_guard_idx = layout.index("if product_luxury_surface?")
    caprasimo_idx = layout.index("Caprasimo")
    assert luxury_guard_idx, "amber layout missing product_luxury_surface? guard"
    assert caprasimo_idx, "amber layout missing Caprasimo font link"
    assert luxury_guard_idx < caprasimo_idx, "Caprasimo must be gated behind product_luxury_surface?"
    assert_includes helper, "def product_luxury_surface?"
    assert_includes helper, "def body_surface_classes"
  end

  private

  def compiled_css_path(app)
    app_css = File.join(ROOT, app, "app", "assets", "builds", "app.css")
    return app_css if File.file?(app_css)

    File.join(ROOT, app, "app", "assets", "builds", "application.css")
  end

  def mixin_block(scss, name)
    start = scss.index("@mixin #{name}")
    assert start, "_x_base.scss missing @mixin #{name}"
    next_mixin = scss.index("@mixin", start + 1)
    scss[start...(next_mixin || scss.length)]
  end
end