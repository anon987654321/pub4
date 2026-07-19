# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"

class TestWebScanFixtures < Minitest::Test
  def rule(id)
    candidates = Master::Review::Scan::Rule.registry.filter_map do |klass|
      instance = klass.new
      instance if instance.id == id
    rescue ArgumentError
      nil
    end
    candidates.first || flunk("missing rule #{id}")
  end

  def assert_finding(rule, code, path, message)
    findings = rule.check(code, path:)
    refute_empty findings
    assert findings.any? { |finding| finding[:message].include?(message) },
      "expected #{rule.id} containing #{message.inspect}, got #{findings.inspect}"
  end

  def test_html_lang_flags_missing_lang
    assert_finding rule("HTML_LANG"), "<html><body></body></html>", "page.html", "lang="
  end

  def test_meta_charset_flags_missing_charset
    assert_finding rule("META_CHARSET"), "<html><head><title>x</title></head></html>", "page.html", "charset"
  end

  def test_img_alt_flags_missing_alt
    assert_finding rule("IMG_ALT"), '<img src="logo.png">', "page.html", "alt="
  end

  def test_lazy_images_flags_missing_loading
    assert_finding rule("LAZY_IMAGES"), '<img src="a.png" alt="a">', "page.html", "loading=lazy"
  end

  def test_button_over_anchor_flags_hash_link
    assert_finding rule("BUTTON_OVER_ANCHOR"), '<a href="#">Click</a>', "page.html", "<button>"
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

    %w[HTML_LANG META_CHARSET IMG_ALT BUTTON_OVER_ANCHOR].each do |id|
      assert_empty rule(id).check(code, path: "clean.html"), "expected no #{id} findings"
    end
  end
end