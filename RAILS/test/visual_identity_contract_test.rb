# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../MASTER/tools/master_design"

class VisualIdentityContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  FACE_SOURCE = File.join(ROOT, "master", "styles", "face", "10_foundation.css")
  FACE_COMPILED = File.join(ROOT, "master", "public", "face.css")
  BRGEN_NAV = File.join(ROOT, "brgen", "app", "assets", "stylesheets", "_brgen_shared_typography.scss")
  BRGEN_STEPS = File.join(ROOT, "brgen", "app", "assets", "stylesheets", "_brgen_shared_media_feed.scss")
  SHARED_CHROME = File.join(ROOT, "__shared", "app", "assets", "stylesheets", "_layout_chrome.scss")
  BRGEN_POSTS = File.join(ROOT, "brgen", "app", "views", "posts", "index.html.erb")

  def test_signal_is_canonical_original_and_semantically_named
    identity = Operator::MasterDesign.tokens.fetch("visual_identity")

    assert_equal "signal_and_stillness", identity.fetch("name")
    assert_equal "#C8F55F", identity.fetch("signal")
    assert_equal "#101010", identity.fetch("signal_ink")
    assert_equal "#50630A", identity.fetch("signal_on_light")
    assert_equal 0.08, identity.fetch("max_highlight_area_fraction")
    assert identity.fetch("avoid").any? { |rule| rule.include?("protected brand expression") }
  end

  def test_master_selected_command_is_a_high_contrast_signal_state
    [FACE_SOURCE, FACE_COMPILED].each do |path|
      css = File.read(path, encoding: "UTF-8")
      assert_match(/#cmd-palette-list li\[data-active="1"\]\s*\{[^}]*background:\s*var\(--pub4-signal\)[^}]*color:\s*var\(--pub4-signal-ink\)/m, css)
      assert_includes css, "color: var(--pub4-signal-ink);"
    end
  end

  def test_brgen_signal_is_a_selected_marker_not_a_forced_brand_palette
    nav = File.read(BRGEN_NAV, encoding: "UTF-8")
    steps = File.read(BRGEN_STEPS, encoding: "UTF-8")

    assert_includes nav, "border-block-end-color: var(--pub4-signal);"
    assert_includes nav, "border-block-end-color: var(--pub4-signal-on-light);"
    assert_includes steps, "border-block-end: 2px solid var(--pub4-signal);"
    assert_includes steps, "border-block-end-color: var(--pub4-signal-on-light);"
  end

  def test_display_scale_is_opt_in_and_used_for_one_primary_editorial_heading
    css = File.read(SHARED_CHROME, encoding: "UTF-8")
    view = File.read(BRGEN_POSTS, encoding: "UTF-8")

    assert_includes css, ".page-header h1.pub4-display-title"
    assert_includes css, "font-size: var(--text-display);"
    assert_includes view, 'class: "pub4-display-title"'
  end

  def test_product_dialects_remain_explicit_in_the_visual_contract
    identity = Operator::MasterDesign.tokens.fetch("visual_identity")
    adapters = identity.fetch("adaptations")

    assert_includes adapters.fetch("brgen"), "deep-blue"
    assert_includes adapters.fetch("amber"), "garment colour"
    assert_includes adapters.fetch("bsdports"), "terminal green"
    assert_includes adapters.fetch("openbsd"), "plain operational text"
    assert_includes adapters.fetch("studio"), "operator-owned"
  end
end
