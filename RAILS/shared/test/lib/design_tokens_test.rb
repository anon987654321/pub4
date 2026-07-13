# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "yaml"
require_relative "../../../design_tokens"

class DesignTokensTest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  FACE_CSS = File.join(ROOT, "..", "MASTER", "web", "public", "face.css")
  UI_YML = File.join(ROOT, "..", "MASTER", "data", "ui.yml")

  CHROME_PANEL_RULES = {
    "#cmd-palette-panel" => %w[--chrome-border --chrome-radius-card --chrome-surface-elevated],
    "#chat-history-panel" => %w[--chrome-border --chrome-radius-md --chrome-surface-elevated],
    ".face-controls" => %w[--chrome-border --chrome-radius-card],
    ".skip-link" => %w[--chrome-border --chrome-radius-sm],
    "#shortcut-sheet" => %w[--chrome-border --chrome-radius-md],
    ".face-error-banner" => %w[--chrome-border --chrome-radius-md],
    ".action-menu" => %w[--chrome-border --chrome-radius-sm],
  }.freeze

  CHROME_ACTION_RULES = {
    ".msg-body a, .msg-body a:visited" => "--chrome-accent",
    "#spin-btn" => "--chrome-accent",
    ".tool.active" => "--chrome-accent",
    ".message.assistant .msg-actions button:hover" => "--chrome-accent",
  }.freeze

  def test_chrome_css_emits_social_aliases_and_derived_hovers
    social = DesignTokens.load.fetch("social")
    css = DesignTokens.chrome_css

    assert_includes css, ":root {"
    DesignTokens::CHROME_ORDER.each do |key|
      var = DesignTokens.chrome_var_name(key)
      assert_includes css, "#{var}: #{social.fetch(key)};", "missing #{var}"
    end
    DesignTokens::CHROME_DERIVED.each do |key, value|
      var = DesignTokens.chrome_var_name(key)
      assert_includes css, "#{var}: #{value};", "missing derived #{var}"
    end
  end

  def test_chrome_block_has_generated_markers
    block = DesignTokens.chrome_block

    assert_includes block, "BEGIN:generated-x-chrome"
    assert_includes block, "END:generated-x-chrome"
    assert_includes block, "generate_face_root_css.rb"
  end

  def test_chrome_var_name_maps_x_prefix_to_chrome
    assert_equal "--chrome-border", DesignTokens.chrome_var_name("x_border")
    assert_equal "--chrome-accent-hover", DesignTokens.chrome_var_name("x_accent_hover")
    assert_equal "--chrome-radius-card", DesignTokens.chrome_var_name("x_radius_card")
  end

  def test_sync_chrome_css_updates_drifted_block
    social = DesignTokens.load.fetch("social")
    stale_accent = social.fetch("x_accent") == "#1d9bf0" ? "#abcdef" : "#1d9bf0"

    Dir.mktmpdir do |dir|
      path = File.join(dir, "face.css")
      File.write(path, <<~CSS)
        /* BEGIN:generated-x-chrome — ruby RAILS/scripts/generate_face_root_css.rb */
        :root {
          --chrome-accent: #{stale_accent};
        }
        /* END:generated-x-chrome */
      CSS

      assert DesignTokens.sync_chrome_css!(path)
      body = File.read(path)
      assert_includes body, "--chrome-accent: #{social.fetch('x_accent')};"
      refute_includes body, stale_accent
    end
  end

  def test_sync_chrome_css_noop_when_in_sync
    Dir.mktmpdir do |dir|
      path = File.join(dir, "face.css")
      File.write(path, "#{DesignTokens.chrome_block}\n")

      refute DesignTokens.sync_chrome_css!(path)
    end
  end

  def test_chrome_drift_detects_mismatch
    Dir.mktmpdir do |dir|
      path = File.join(dir, "face.css")
      File.write(path, <<~CSS)
        /* BEGIN:generated-x-chrome — ruby RAILS/scripts/generate_face_root_css.rb */
        :root {
          --chrome-accent: #000000;
        }
        /* END:generated-x-chrome */
      CSS

      drift = DesignTokens.chrome_drift?(path)
      refute_nil drift
      assert_includes drift, "x-chrome drift"
    end
  end

  def test_chrome_drift_nil_when_in_sync
    skip "face.css not present" unless File.file?(FACE_CSS)

    refute DesignTokens.chrome_drift?(FACE_CSS)
  end

  def test_face_root_drift_nil_for_checked_in_face_css
    skip "face.css not present" unless File.file?(FACE_CSS)

    refute DesignTokens.face_root_drift?(FACE_CSS)
  end

  def test_sync_face_chrome_css_updates_both_blocks
    Dir.mktmpdir do |dir|
      path = File.join(dir, "face.css")
      File.write(path, <<~CSS)
        /* BEGIN:generated-face-root — ruby RAILS/scripts/generate_face_root_css.rb */
        :root { --stale: 1; }
        /* END:generated-face-root */
        /* BEGIN:generated-x-chrome — ruby RAILS/scripts/generate_face_root_css.rb */
        :root { --chrome-accent: #000000; }
        /* END:generated-x-chrome */
      CSS

      changed, face_changed, chrome_changed = DesignTokens.sync_face_chrome_css!(path)
      assert changed
      assert face_changed
      assert chrome_changed
      body = File.read(path)
      assert_includes body, DesignTokens.face_root_css
      assert_includes body, DesignTokens.chrome_css
    end
  end

  def test_master_chrome_contract_in_face_css
    skip "face.css not present" unless File.file?(FACE_CSS)
    skip "ui.yml not present" unless File.file?(UI_YML)

    css = File.read(FACE_CSS)
    chrome_tier = YAML.safe_load_file(UI_YML).fetch("chrome_tier")

    assert_equal "cream_body_blue_actions_only", chrome_tier.fetch("message_treatment")
    assert_match(/\.msg-body\s*\{[^}]*var\(--c-text\)/m, css, "msg-body must stay cream via --c-text")

    CHROME_PANEL_RULES.each do |selector, tokens|
      rule = rule_block(css, selector, must_include: tokens.first)
      assert rule, "missing #{selector} chrome rule block"
      tokens.each do |token|
        assert_includes rule, token, "#{selector} must use #{token}"
      end
    end

    CHROME_ACTION_RULES.each do |selector, token|
      rule = rule_block(css, selector, must_include: token)
      assert rule, "missing #{selector} chrome rule block"
      assert_includes rule, token, "#{selector} must use #{token}"
    end
  end

  private

  def rule_block(css, selector, must_include: nil)
    blocks = css.scan(/#{Regexp.escape(selector)}\s*\{([^}]*)\}/m).map(&:first)
    return blocks.find { |body| body.include?(must_include) } if must_include

    blocks.max_by(&:length)
  end
end