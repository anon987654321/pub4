# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"

class TestWebScanFixtures < Minitest::Test
  # BUTTON_OVER_ANCHOR lives once, in law/ — its scanner surface is the
  # bridge, so its fixture asserts through it.
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
    assert_finding rule("IMG_ALT"), '<img src="logo.png">', "page.html", "alt="
  end

  # The tag, not the line: attribute-per-line markup and ERB inside an
  # attribute both defeated the per-line law twin (its lookahead stopped at
  # the %> of an interpolation), which is why these two live in the registry.
  def test_img_alt_reads_the_whole_tag
    multi = %(<img loading="lazy"\n     src="<%= deal.image_url %>"\n     alt="ok">)
    assert_empty rule("IMG_ALT").check(multi, path: "page.html.erb")
  end

  def test_lazy_images_flags_missing_loading
    assert_finding rule("LAZY_IMAGES"), '<img src="a.png" alt="a">', "page.html", "loading=lazy"
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
    assert_empty rule("IMG_ALT").check(code, path: "clean.html"), "expected no IMG_ALT findings"
    assert_empty law_findings("BUTTON_OVER_ANCHOR", code, path: "clean.html"), "expected no BUTTON_OVER_ANCHOR findings"
  end
end
