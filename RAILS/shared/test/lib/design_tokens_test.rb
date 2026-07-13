# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../../design_tokens"

class DesignTokensTest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)
  FACE_CSS = File.join(ROOT, "..", "MASTER", "web", "public", "face.css")

  def test_chrome_css_emits_social_aliases
    social = DesignTokens.load.fetch("social")
    css = DesignTokens.chrome_css

    assert_includes css, ":root {"
    DesignTokens::CHROME_ORDER.each do |key|
      var = DesignTokens.chrome_var_name(key)
      assert_includes css, "#{var}: #{social.fetch(key)};", "missing #{var}"
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
end