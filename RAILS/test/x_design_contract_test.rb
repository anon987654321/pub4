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
  BSDPORTS_LAYOUT = File.join(ROOT, "bsdports", "app", "views", "layouts", "application.html.erb")
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
      css = File.join(ROOT, app, "app", "assets", "builds", "application.css")
      next unless File.file?(css)

      refute_match(CYCLIC_X_DANGER_PATTERN, File.read(css), "#{app} application.css has cyclic --x-danger")
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

  private

  def mixin_block(scss, name)
    start = scss.index("@mixin #{name}")
    assert start, "_x_base.scss missing @mixin #{name}"
    next_mixin = scss.index("@mixin", start + 1)
    scss[start...(next_mixin || scss.length)]
  end
end