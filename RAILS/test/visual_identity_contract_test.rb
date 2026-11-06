# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../MASTER/tools/master_design"
require_relative "support/stylesheet_modules"

class VisualIdentityContractTest < Minitest::Test
  include StylesheetModules

  ROOT = File.expand_path("..", __dir__)
  FACE_SOURCE = File.join(ROOT, "..", "MASTER", "web", "styles", "face", "10_foundation.css")
  FACE_COMPILED = File.join(ROOT, "..", "MASTER", "web", "public", "face.css")
  SHARED_CHROME = File.join(ROOT, "__shared", "app", "assets", "stylesheets", "_layout_chrome.scss")
  BRGEN_POSTS = File.join(ROOT, "brgen", "app", "views", "posts", "index.html.erb")
  AMBER_LAYOUT = File.join(ROOT, "amber", "app", "views", "layouts", "application.html.erb")
  AMBER_SIDEBAR = File.join(ROOT, "amber", "app", "views", "shared", "_sidebar_nav.html.erb")
  AMBER_HELPER = File.join(ROOT, "amber", "app", "helpers", "application_helper.rb")
  AMBER_STYLES =File.join(ROOT, "amber", "app", "assets", "stylesheets", "application.scss")
  BSDPORTS_STYLES = File.join(ROOT, "bsdports", "app", "assets", "stylesheets", "application.scss")
  BSDPORTS_LAYOUT = File.join(ROOT, "bsdports", "app", "views", "layouts", "application.html.erb")
  # The face's motion and accessibility rules, split by concern across 40-44.
  FACE_MOTION = Dir[File.join(ROOT, "..", "MASTER", "web", "styles", "face", "4[0-4]_*.css")].sort
  SHARED_MOTION = File.join(ROOT, "__shared", "app", "assets", "stylesheets", "_interaction_craft.scss")
  # laws.yml states each Law; law_runtime.yml carries the executable requirements.
  LAW_FILES = %w[laws.yml law_runtime.yml].map { |name| File.expand_path("../../MASTER/data/#{name}", __dir__) }
  LAWS_SOURCE = LAW_FILES.map { |path| File.read(path, encoding: "UTF-8") }.join("\n")

  def test_signal_is_canonical_original_and_semantically_named
    identity = Operator::MasterDesign.tokens.fetch("visual_identity")

    assert_equal "signal_and_stillness", identity.fetch("name")
    assert_equal "#C8F55F", identity.fetch("signal")
    assert_equal "#101010", identity.fetch("signal_ink")
    assert_equal "#50630A", identity.fetch("signal_on_light")
    assert_equal 0.08, identity.fetch("max_highlight_area_fraction")
    assert_equal "clamp(40px, 6vw, 88px)", identity.fetch("display_size")
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
    # brgen is split into @use partials; stylesheet_source reads them all.
    nav = stylesheet_source("brgen")
    steps = nav

    assert_includes nav, "border-block-end-color: var(--pub4-signal);"
    assert_includes nav, "border-block-end-color: var(--pub4-signal-on-light);"
    assert_includes steps, "border-block-end: 2px solid var(--pub4-signal);"
    assert_includes steps, "border-block-end-color: var(--pub4-signal-on-light);"
  end

  def test_selected_sort_state_uses_the_signal_without_repainting_the_product_palette
    css = stylesheet_source("brgen")

    assert_includes css, "border-block-end-color: var(--pub4-signal);"
    assert_includes css, ':root[data-theme="light"] .sort-tab.active'
    assert_includes css, "border-block-end-color: var(--pub4-signal-on-light);"
  end

  def test_amber_uses_semantic_current_page_and_signal_ink_without_recolouring_photography
    sidebar = File.read(AMBER_SIDEBAR, encoding: "UTF-8")
    styles = File.read(AMBER_STYLES, encoding: "UTF-8")

    helper = File.read(AMBER_HELPER, encoding: "UTF-8")

    # The sidebar marks its current link through nav_current, which answers
    # "page" on the exact page and "true" anywhere else in that section.
    assert_includes sidebar, 'aria: { current: nav_current(items_path, section: "items") }'
    assert_includes sidebar, 'aria: { current: nav_current(outfits_path, section: "outfits"'
    assert_includes helper, 'return "page" if current_page?(path)'
    assert_includes styles, ".sidebar .nav-item[aria-current]"
    assert_includes styles, "color: var(--pub4-signal-on-light);"
    refute_match(/\.item-photo\s*\{[^}]*filter:/m, styles,
                 "the aesthetic must not tint garment/product photography")
  end

  def test_bsdports_keeps_classic_google_white_frontpage_palette
    styles = File.read(BSDPORTS_STYLES, encoding: "UTF-8")
    layout = File.read(BSDPORTS_LAYOUT, encoding: "UTF-8")

    assert_includes styles, "nav[data-pwa-primary-nav] a[aria-current]"

    assert_includes styles, "color: var(--accent);"
    assert_includes styles, "text-decoration-thickness: 2px;"
    assert_includes styles, "--text: #202124;"
    assert_includes styles, "--text-secondary: #4d5156;"
    assert_includes styles, "--accent: #1a0dab;"
    assert_includes styles, '--font: Arial, "Helvetica Neue", Helvetica, sans-serif;'
    assert_includes styles, "color-scheme: light;"
    assert_includes layout, %(<meta name="color-scheme" content="light">)
    assert_includes layout, %(<meta name="theme-color" content="#ffffff" data-light-color="#ffffff" data-dark-color="#000000">)
  end

  def test_display_scale_is_opt_in_and_used_for_one_primary_editorial_heading
    css = File.read(SHARED_CHROME, encoding: "UTF-8")
    view = File.read(BRGEN_POSTS, encoding: "UTF-8")

    assert_includes css, ".page-header h1.primary-title"
    assert_includes css, "font-size: var(--text-display);"
    assert_includes css, "line-height: var(--leading-none);"
    assert_includes view, 'class: "primary-title"'
    refute_match(/pub4-display-title/, css + view)
  end

  def test_face_display_weight_tokens_live_outside_the_generated_root
    foundation = File.read(File.join(ROOT, "..", "MASTER", "web", "styles", "face", "10_foundation.css"))
    display = File.read(File.join(ROOT, "..", "MASTER", "web", "styles", "face", "43_face_chrome.css"))
    compiled = File.read(FACE_COMPILED)
    generated = compiled.split("/* BEGIN:generated-face-root", 2).last.split("/* END:generated-face-root */", 2).first

    assert_includes foundation, "--face-weight-brand: 640;"
    assert_includes foundation, "--face-weight-display: 560;"
    assert_includes display, "font-weight: var(--face-weight-brand);"
    assert_includes display, "font-weight: var(--face-weight-display);"
    refute_includes generated, "--face-weight-brand"
    refute_includes generated, "--face-weight-display"
    assert_includes compiled, "font-weight: var(--face-weight-brand);"
    assert_includes compiled, "font-weight: var(--face-weight-display);"
  end

  def test_reduced_motion_preserves_meaning_without_perpetual_animation
    identity = Operator::MasterDesign.tokens.fetch("visual_identity")
    face_motion = FACE_MOTION.map { |path| File.read(path, encoding: "UTF-8") }.join("\n")
    shared_motion = File.read(SHARED_MOTION, encoding: "UTF-8")

    assert_equal "still", identity.dig("motion", "default")
    assert_equal true, identity.dig("motion", "reduced_motion_must_preserve_meaning")
    assert_includes face_motion, "prefers-reduced-motion: reduce"
    assert_includes shared_motion, "prefers-reduced-motion: reduce"
    assert_includes shared_motion, "animation: none;"
  end

  def test_canonical_visual_contract_requires_runtime_and_performance_proof
    %w[
      reduced_motion_runtime
      aggregate_render_budget
      renderer_lifecycle
      render_state_regression
      device_performance_evidence
    ].each { |requirement| assert_includes LAWS_SOURCE, requirement }

    assert_includes LAWS_SOURCE, "Reduced-motion policy applies to every animated layer and transition"
    assert_includes LAWS_SOURCE, "no adapter may spend the whole renderer budget independently"
    assert_includes LAWS_SOURCE, "JavaScript render-call cadence from GPU completion"
  end

  def test_product_dialects_remain_explicit_in_the_visual_contract
    identity = Operator::MasterDesign.tokens.fetch("visual_identity")
    adapters = identity.fetch("adaptations")

    assert_includes adapters.fetch("brgen"), "deep-blue"
    assert_includes adapters.fetch("amber"), "garment colour"
    # BSDPorts is the classic search front page; see the test below.
    assert_includes File.read(BSDPORTS_STYLES, encoding: "UTF-8"), "--accent: #1a0dab;"
    assert_includes adapters.fetch("openbsd"), "plain operational text"
    assert_includes adapters.fetch("studio"), "operator-owned"

    art = identity.fetch("art_direction")
    type_roles = identity.fetch("typography_roles")
    assert_equal 1, art.fetch("subject_count")
    assert_equal true, art.fetch("preserve_media_colour")
    assert_equal true, art.fetch("preserve_likeness")
    assert_equal true, art.fetch("grade_is_explicit")
    assert_includes art.fetch("typography_layer"), "editable"
    assert_equal "text-display", type_roles.fetch("display")
    assert_equal "text-base", type_roles.fetch("body")
    assert_equal "font-mono", type_roles.fetch("technical")
    assert_includes type_roles.fetch("wordmark"), "original"
  end

  # BSDPorts is ultraminimal white, the classic search front page (operator,
  # 2026-10-31); MASTER's adaptation said "terminal green" until then, which
  # RAILS/apps.yml and the rendered stylesheet never did.
  def test_bsdports_adaptation_matches_its_product
    adapters = Operator::MasterDesign.tokens.fetch("visual_identity").fetch("adaptations")

    assert_includes adapters.fetch("bsdports"), "ultraminimal white"
    refute_includes adapters.fetch("bsdports"), "terminal green"
  end
end
