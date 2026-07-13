# frozen_string_literal: true

require "yaml"
require "minitest/autorun"

class XDesignContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  SHARED = File.join(ROOT, "shared")
  X_BASE = File.join(SHARED, "app", "assets", "stylesheets", "_x_base.scss")
  TOKENS_YML = File.join(SHARED, "design_tokens.yml")
  BRGEN_ROOT = File.join(ROOT, "brgen", "app", "assets", "stylesheets", "_root.scss")
  BUILD_ALL_CSS = File.join(ROOT, "build_all_css.rb")
  BSDPORTS_LAYOUT = File.join(ROOT, "bsdports", "app", "views", "layouts", "application.html.erb")

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

  SYSTEM_UI_FONT = '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif'.freeze
  FLAT_DESIGN_PATTERN = /box-shadow|text-shadow|backdrop-filter/i

  def test_social_tokens_match_x_base_defaults
    social = YAML.safe_load_file(TOKENS_YML).fetch("social")
    scss = File.read(X_BASE)

    SCSS_PARAM_MAP.each do |yaml_key, scss_param|
      expected = social.fetch(yaml_key)
      pattern = /\$#{Regexp.escape(scss_param)}:\s*(#[0-9a-f]{3,8})/i
      match = scss.match(pattern)
      assert match, "_x_base.scss missing default for $#{scss_param}"
      assert_equal expected.downcase, match[1].downcase, "drift: #{yaml_key}"
    end

    SCSS_LITERAL_MAP.each do |yaml_key, pattern|
      expected = social.fetch(yaml_key).strip
      match = scss.match(pattern)
      assert match, "_x_base.scss missing literal for #{yaml_key}"
      assert_equal expected, match[1].strip, "drift: #{yaml_key}"
    end

    assert_includes scss, "--x-font: #{SYSTEM_UI_FONT};"
    assert_equal social.fetch("x_font"), SYSTEM_UI_FONT
  end

  def test_brgen_does_not_override_x_accent
    root_scss = File.read(BRGEN_ROOT)
    refute_includes root_scss, "--x-accent: #1d55f0"
    refute_match(/--x-accent:\s*#[0-9a-f]{6}/i, root_scss)
  end

  def test_tokens_scss_defines_semantic_status_aliases
    tokens = File.read(File.join(SHARED, "app", "assets", "stylesheets", "_tokens.scss"))
    assert_includes tokens, "@include x.x-semantic-status-tokens;"
    assert_includes File.read(X_BASE), "--x-success: var(--color-success);"
    assert_includes File.read(X_BASE), "--x-like-active: var(--x-accent);"
    refute_includes File.read(TOKENS_YML), "x_like_active:"
  end

  def test_build_all_css_syncs_system_ui_font_and_layout_vars
    body = File.read(BUILD_ALL_CSS)
    refute_includes body, '--x-font: "JetBrainsMono Nerd Font"'
    assert_includes body, "--x-font: #{SYSTEM_UI_FONT};"
    %w[--x-sidebar --x-feed-max --x-widgets --x-layout-max --x-accent-hover].each do |token|
      assert_includes body, token, "build_all_css.rb missing #{token}"
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
end