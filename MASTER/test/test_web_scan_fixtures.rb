# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"

class TestWebScanFixtures < Minitest::Test
  # IMG_ALT, LAZY_IMAGES and BUTTON_OVER_ANCHOR live once, in law/ — their
  # scanner surface is the bridge, so these fixtures assert through it.
  def law_findings(id, code, path:)
    Master::Review::Scan::Rules::LawBridgeRule.new.check(code, path:).select { |f| f[:rule] == id }
  end

  def test_html_lang_flags_missing_lang
    assert_finding rule("HTML_LANG"), "<html><body></body></html>", "page.html", "lang="
  end

  def test_meta_charset_flags_missing_charset
    assert_finding rule("META_CHARSET"), "<html><head><title>x</title></head></html>", "page.html", "charset"
  end

  def test_img_alt_flags_missing_alt
    refute_empty law_findings("IMG_ALT", '<img src="logo.png">', path: "page.html")
  end

  def test_lazy_images_flags_missing_loading
    refute_empty law_findings("LAZY_IMAGES", '<img src="a.png" alt="a">', path: "page.html")
  end

  def test_button_over_anchor_flags_hash_link
    refute_empty law_findings("BUTTON_OVER_ANCHOR", '<a href="#">Click</a>', path: "page.html")
  end

  def test_magic_color_flags_raw_hex_in_css
    assert_finding rule("MAGIC_COLOR"), ".btn { color: #ff00aa; }", "app.css", "raw hex"
  end

  def test_no_var_flags_var_in_js
    assert_finding rule("NO_VAR"), "var count = 1;\n", "app.js", "var "
  end

  def test_clean_layout_passes_core_rules
    code = <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>ok</title>
      </head>
      <body>
        <img src="x.png" alt="x" loading="lazy">
        <button type="button">Go</button>
      </body>
      </html>
    HTML

    %w[HTML_LANG META_CHARSET].each do |id|
      assert_empty rule(id).check(code, path: "clean.html"), "expected no #{id} findings"
    end
    %w[IMG_ALT BUTTON_OVER_ANCHOR].each do |id|
      assert_empty law_findings(id, code, path: "clean.html"), "expected no #{id} findings"
    end
  end
end
